import asyncio
import json
import os
import sys
import uuid

import aiofiles
import websockets
from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer
from websockets.server import WebSocketServerProtocol
from typing import Set

all_websocket: Set[WebSocketServerProtocol] = set()
js_file_path = ""
last_modified_time = None
clients_lock = asyncio.Lock()

CHUNK_SIZE = 1024 * 5


def print_red(text):
    print("\033[31m" + text + "\033[0m")


class JSFileHandler(FileSystemEventHandler):

    def __init__(self, filepath, loop):
        super().__init__()
        self.filepath = filepath
        self.loop = loop

    def on_modified(self, event):
        if event.src_path == self.filepath:
            current_time = os.path.getmtime(self.filepath)
            global last_modified_time
            if current_time == last_modified_time:
                return
            asyncio.run_coroutine_threadsafe(send_updated_file(self.filepath), self.loop)
            last_modified_time = current_time


async def send_updated_file(filepath):
    try:
        if all_websocket:
            async with clients_lock:
                to_remove = set()
                for websocket in all_websocket:
                    file_size = os.path.getsize(js_file_path)
                    if file_size > 1024:
                        chunk_total = (file_size + CHUNK_SIZE - 1) // CHUNK_SIZE
                        chunk_id = str(uuid.uuid4())

                        async with aiofiles.open(js_file_path, "r", encoding="utf-8") as file:
                            for chunk_index in range(chunk_total):
                                chunk_data = await file.read(CHUNK_SIZE)
                                chunk_message = json.dumps({
                                    "type": "script",
                                    "big_script": True,
                                    "chunk_id": chunk_id,
                                    "chunk_total": chunk_total,
                                    "chunk_index": chunk_index,
                                    "chunk_data": chunk_data,
                                })
                                try:
                                    await websocket.send(chunk_message)
                                except Exception as e:
                                    print(f"Send failed: {e}")
                                    to_remove.add(websocket)
                                    break
                    else:
                        async with aiofiles.open(filepath, "r", encoding="utf-8") as file:
                            updated_content = await file.read()
                        message = json.dumps({"type": "script", "script": updated_content})
                        try:
                            await websocket.send(message)
                        except Exception as e:
                            print(f"Send failed: {e}")
                            to_remove.add(websocket)
                for websocket in to_remove:
                    try:
                        await websocket.close()
                    except Exception as e:
                        print("Close error", e)
                    all_websocket.remove(websocket)
    except Exception as e:
        print(f"Push error: {e}")


async def handle_client(websocket: WebSocketServerProtocol, path: str):
    all_websocket.add(websocket)
    print(f"Client connected: {websocket.remote_address}")
    if path == "/ws":
        try:
            async for message_string in websocket:
                message = json.loads(message_string)
                if message["type"] == "start":
                    file_size = os.path.getsize(js_file_path)
                    if file_size > 1024:
                        chunk_total = (file_size + CHUNK_SIZE - 1) // CHUNK_SIZE
                        chunk_id = str(uuid.uuid4())

                        async with aiofiles.open(js_file_path, "r", encoding="utf-8") as file:
                            for chunk_index in range(chunk_total):
                                chunk_data = await file.read(CHUNK_SIZE)
                                chunk_message = json.dumps({
                                    "type": "start",
                                    "big_script": True,
                                    "chunk_id": chunk_id,
                                    "chunk_total": chunk_total,
                                    "chunk_index": chunk_index,
                                    "chunk_data": chunk_data,
                                })
                                await websocket.send(chunk_message)
                    else:
                        async with aiofiles.open(js_file_path, "r", encoding="utf-8") as file:
                            initial_content = await file.read()
                        initial_message = json.dumps({"type": "start", "script": initial_content})
                        await websocket.send(initial_message)
                elif message["type"] == "log":
                    print(message["payload"])
                elif message["type"] == "error":
                    print_red("error: " + message["description"])
                    print_red(message["stack"])
                else:
                    print_red(str(message))
        except websockets.ConnectionClosed as e:
            print(f"Disconnected: {websocket.remote_address}")
            all_websocket.remove(websocket)
        except OSError as e:
            print(f"Disconnected: {websocket.remote_address}")
            try:
                await websocket.close()
            except Exception as e:
                print(e)
            all_websocket.remove(websocket)


async def main_async(loop):
    global js_file_path, last_modified_time

    if len(sys.argv) != 2:
        print("Usage: python server.py <path_to_js_file>")
        sys.exit(1)

    js_file_path = sys.argv[1]

    if not os.path.isfile(js_file_path):
        print(f"Error: {js_file_path} does not exist")
        sys.exit(1)

    last_modified_time = os.path.getmtime(js_file_path)

    event_handler = JSFileHandler(js_file_path, loop)
    observer = Observer()
    observer.schedule(event_handler, path=os.path.dirname(js_file_path), recursive=False)
    observer.start()

    server = await websockets.serve(handle_client, "0.0.0.0", 14725)
    print("WebSocket server started: ws://0.0.0.0:14725/ws")
    await server.wait_closed()

    observer.stop()
    observer.join()


def main():
    loop = asyncio.get_event_loop()
    try:
        loop.run_until_complete(main_async(loop))
    except KeyboardInterrupt:
        print("Server shutting down...")
    finally:
        loop.close()


if __name__ == "__main__":
    main()
