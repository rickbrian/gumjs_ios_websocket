// 诊断：手动 dlopen 引擎库，捕获 dyld 的精确错误
// 用法见对话说明
'use strict';

var ENGINE = "/var/jb/usr/lib/libGJWSEngine.dylib";

console.log("[*] process: " + Process.id);
console.log("[*] trying Module.load(" + ENGINE + ") ...");

try {
    var m = Module.load(ENGINE);
    console.log("[+] LOADED OK: " + m.name + " @ " + m.base + " size=" + m.size);
    try {
        var s = Module.findExportByName("libGJWSEngine.dylib", "gjws_start");
        console.log("[+] gjws_start export = " + s);
    } catch (e2) {
        console.log("[-] findExport gjws_start failed: " + e2.message);
    }
} catch (e) {
    console.log("[-] LOAD FAILED: " + e.message);
}

// 备用：直接调底层 dlopen，拿 dlerror() 字符串
try {
    var dlopen = new NativeFunction(Module.getGlobalExportByName("dlopen"), 'pointer', ['pointer', 'int']);
    var dlerror = new NativeFunction(Module.getGlobalExportByName("dlerror"), 'pointer', []);
    var RTLD_NOW = 2;
    var h = dlopen(Memory.allocUtf8String(ENGINE), RTLD_NOW);
    console.log("[*] raw dlopen handle = " + h);
    if (h.isNull()) {
        var err = dlerror();
        console.log("[-] raw dlerror = " + (err.isNull() ? "(null)" : err.readUtf8String()));
    }
} catch (e3) {
    console.log("[-] raw dlopen test failed: " + e3.message);
}
