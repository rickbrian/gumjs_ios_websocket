//
//  GJWSWebSocket.h
//  自包含 WebSocket 客户端 (RFC 6455, 纯 BSD socket)
//
//  设计目标: 引擎与 PC 端的通讯完全建立在最底层的 POSIX socket 之上
//  (socket/connect/send/recv/close), 不依赖 NSURLSession / CFNetwork / SSL,
//  这样目标 App 内的脚本去 hook 任何高层网络库都不会波及到本通道。
//
//  仅支持 ws:// (明文), 用于局域网调试场景。
//

#pragma once

#include <string>
#include <vector>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <mutex>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <errno.h>

class GJWSWebSocket {
public:
    GJWSWebSocket() : _fd(-1) {}
    ~GJWSWebSocket() { closeSocket(); }

    int fd() const { return _fd; }

    // 解析 ws://host:port/path
    static bool parseURI(const std::string &uri, std::string &host,
                         int &port, std::string &path) {
        const std::string prefix = "ws://";
        if (uri.rfind(prefix, 0) != 0) return false;
        std::string s = uri.substr(prefix.size());

        std::string hostport;
        size_t slash = s.find('/');
        if (slash == std::string::npos) {
            hostport = s;
            path = "/";
        } else {
            hostport = s.substr(0, slash);
            path = s.substr(slash);
        }

        size_t colon = hostport.find(':');
        if (colon == std::string::npos) {
            host = hostport;
            port = 80;
        } else {
            host = hostport.substr(0, colon);
            port = atoi(hostport.substr(colon + 1).c_str());
        }
        return !host.empty() && port > 0;
    }

    // 连接 + 完成 WebSocket 握手; 成功返回 true
    bool connectTo(const std::string &host, int port, const std::string &path) {
        closeSocket();

        struct addrinfo hints;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        char portstr[16];
        snprintf(portstr, sizeof(portstr), "%d", port);

        struct addrinfo *res = NULL;
        if (getaddrinfo(host.c_str(), portstr, &hints, &res) != 0 || !res)
            return false;

        int fd = -1;
        for (struct addrinfo *p = res; p; p = p->ai_next) {
            fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
            if (fd < 0) continue;
            if (::connect(fd, p->ai_addr, p->ai_addrlen) == 0) break;
            ::close(fd);
            fd = -1;
        }
        freeaddrinfo(res);
        if (fd < 0) return false;

        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

        {
            std::lock_guard<std::mutex> lk(_sendMutex);
            _fd = fd;
        }

        if (!handshake(host, port, path)) {
            closeSocket();
            return false;
        }
        return true;
    }

    // 阻塞接收一条完整消息。
    // 返回:  1 = 收到文本消息 (写入 out);  0 = 控制/二进制帧 (忽略, 继续循环);
    //       -1 = 连接关闭或出错
    int recvMessage(std::string &out) {
        out.clear();
        int dataOpcode = 0;

        for (;;) {
            uint8_t hdr[2];
            if (!readFull(hdr, 2)) return -1;

            bool fin = (hdr[0] & 0x80) != 0;
            int op = hdr[0] & 0x0F;
            bool masked = (hdr[1] & 0x80) != 0;
            uint64_t len = hdr[1] & 0x7F;

            if (len == 126) {
                uint8_t e[2];
                if (!readFull(e, 2)) return -1;
                len = ((uint64_t)e[0] << 8) | e[1];
            } else if (len == 127) {
                uint8_t e[8];
                if (!readFull(e, 8)) return -1;
                len = 0;
                for (int i = 0; i < 8; i++) len = (len << 8) | e[i];
            }

            uint8_t mask[4] = {0, 0, 0, 0};
            if (masked && !readFull(mask, 4)) return -1;

            std::string payload;
            payload.resize((size_t)len);
            if (len > 0 && !readFull((uint8_t *)&payload[0], (size_t)len))
                return -1;
            if (masked)
                for (size_t i = 0; i < payload.size(); i++)
                    payload[i] ^= mask[i & 3];

            if (op == 0x8) {            // close
                return -1;
            } else if (op == 0x9) {     // ping -> pong
                sendFrame(0xA, payload.data(), payload.size());
                continue;
            } else if (op == 0xA) {     // pong
                continue;
            }

            if (op == 0x1 || op == 0x2) {
                dataOpcode = op;
                out += payload;
            } else if (op == 0x0) {     // continuation
                out += payload;
            }

            if (fin) {
                return (dataOpcode == 0x1) ? 1 : 0;
            }
        }
    }

    bool sendText(const std::string &msg) {
        return sendFrame(0x1, msg.data(), msg.size());
    }

    void closeSocket() {
        std::lock_guard<std::mutex> lk(_sendMutex);
        if (_fd >= 0) {
            ::shutdown(_fd, SHUT_RDWR);
            ::close(_fd);
            _fd = -1;
        }
    }

private:
    int _fd;
    std::mutex _sendMutex;   // 保护 send 与 close, 允许收/发并发在不同线程

    bool readFull(uint8_t *buf, size_t n) {
        size_t got = 0;
        while (got < n) {
            ssize_t r = ::recv(_fd, buf + got, n - got, 0);
            if (r > 0) {
                got += (size_t)r;
            } else if (r == 0) {
                return false;
            } else {
                if (errno == EINTR) continue;
                return false;
            }
        }
        return true;
    }

    bool writeFull(const uint8_t *buf, size_t n) {
        size_t sent = 0;
        while (sent < n) {
            ssize_t w = ::send(_fd, buf + sent, n - sent, 0);
            if (w > 0) {
                sent += (size_t)w;
            } else {
                if (errno == EINTR) continue;
                return false;
            }
        }
        return true;
    }

    // 客户端帧必须 mask
    bool sendFrame(int opcode, const void *data, size_t len) {
        std::lock_guard<std::mutex> lk(_sendMutex);
        if (_fd < 0) return false;

        std::vector<uint8_t> frame;
        frame.push_back(0x80 | (uint8_t)(opcode & 0x0F));

        const uint8_t maskbit = 0x80;
        if (len < 126) {
            frame.push_back(maskbit | (uint8_t)len);
        } else if (len <= 0xFFFF) {
            frame.push_back(maskbit | 126);
            frame.push_back((uint8_t)((len >> 8) & 0xFF));
            frame.push_back((uint8_t)(len & 0xFF));
        } else {
            frame.push_back(maskbit | 127);
            for (int i = 7; i >= 0; i--)
                frame.push_back((uint8_t)((len >> (i * 8)) & 0xFF));
        }

        uint8_t mask[4];
        arc4random_buf(mask, sizeof(mask));
        frame.insert(frame.end(), mask, mask + 4);

        size_t hdrlen = frame.size();
        frame.resize(hdrlen + len);
        const uint8_t *src = (const uint8_t *)data;
        for (size_t i = 0; i < len; i++)
            frame[hdrlen + i] = src[i] ^ mask[i & 3];

        return writeFull(frame.data(), frame.size());
    }

    static std::string base64(const uint8_t *data, size_t len) {
        static const char *tbl =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        std::string out;
        size_t i = 0;
        while (i + 3 <= len) {
            uint32_t n = ((uint32_t)data[i] << 16) |
                         ((uint32_t)data[i + 1] << 8) | data[i + 2];
            out += tbl[(n >> 18) & 63];
            out += tbl[(n >> 12) & 63];
            out += tbl[(n >> 6) & 63];
            out += tbl[n & 63];
            i += 3;
        }
        if (len - i == 1) {
            uint32_t n = (uint32_t)data[i] << 16;
            out += tbl[(n >> 18) & 63];
            out += tbl[(n >> 12) & 63];
            out += "==";
        } else if (len - i == 2) {
            uint32_t n = ((uint32_t)data[i] << 16) | ((uint32_t)data[i + 1] << 8);
            out += tbl[(n >> 18) & 63];
            out += tbl[(n >> 12) & 63];
            out += tbl[(n >> 6) & 63];
            out += "=";
        }
        return out;
    }

    bool handshake(const std::string &host, int port, const std::string &path) {
        uint8_t key[16];
        arc4random_buf(key, sizeof(key));
        std::string secKey = base64(key, sizeof(key));

        std::string req;
        req += "GET " + path + " HTTP/1.1\r\n";
        req += "Host: " + host + ":" + std::to_string(port) + "\r\n";
        req += "Upgrade: websocket\r\n";
        req += "Connection: Upgrade\r\n";
        req += "Sec-WebSocket-Key: " + secKey + "\r\n";
        req += "Sec-WebSocket-Version: 13\r\n";
        req += "\r\n";

        if (!writeFull((const uint8_t *)req.data(), req.size())) return false;

        // 逐字节读到 \r\n\r\n 为止, 避免越界读到首个数据帧
        std::string resp;
        char c;
        while (resp.find("\r\n\r\n") == std::string::npos) {
            ssize_t r = ::recv(_fd, &c, 1, 0);
            if (r <= 0) {
                if (r < 0 && errno == EINTR) continue;
                return false;
            }
            resp += c;
            if (resp.size() > 8192) return false;
        }

        return resp.find(" 101 ") != std::string::npos ||
               resp.find("101 Switching") != std::string::npos;
    }
};
