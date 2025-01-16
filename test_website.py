from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
os.chdir("./zig-out/bin/www/")
class CrossOriginIsolatedHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        #Restarting the server/browser doesn't work sometimes with cache resetting. Force cache to expire here.
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Expires", "0")
        self.send_header("Pragma", "no-cache")
        #This is used to interact with SharedArrayBuffer being sent to a Worker (To wasm.js)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
server_address = ('', 8000) 
httpd = HTTPServer(server_address, CrossOriginIsolatedHandler)
print("Serving on http://localhost:8000")
httpd.serve_forever()