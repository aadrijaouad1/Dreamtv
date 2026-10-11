#!/usr/bin/env python3
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlsplit, parse_qs
from socketserver import TCPServer
from pathlib import Path
import json, sys, base64
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path=urlsplit(self.path)
        print("FIXTURE",path.path,flush=True)
        if path.path=='/redirect':
            self.send_response(302);self.send_header('Location','/list.m3u');self.end_headers();return
        if path.path=='/oversize':
            self.send_response(200);self.end_headers()
            try:self.wfile.write(b'x'*32768)
            except (BrokenPipeError, ConnectionResetError):pass
            return
        if path.path=='/html': body=b'<html>unavailable</html>'
        elif path.path=='/list.m3u':body=b'#EXTM3U\n#EXTINF:-1 group-title="Test",Sample\nvideo.m3u8\n'
        elif path.path=='/player_api.php':
            action=parse_qs(path.query).get('action',[''])[0]
            if action.endswith('_categories'):data=[{'category_id':'5','category_name':'Test'}]
            else:data={
                '':{'user_info':{'auth':1}},
                'get_live_streams':[{'stream_id':1,'category_id':'5','name':'Live'}],
                'get_vod_streams':[{'stream_id':2,'category_id':'5','name':'Movie','container_extension':'mp4'}],
                'get_series':[{'series_id':3,'category_id':'5','name':'Series'}],
                'get_series_info':{'episodes':{'1':[{'id':'32','season':1,'episode_num':2,'title':'Episode 2'},{'id':'31','season':1,'episode_num':1,'title':'Episode 1'}]}},
                'get_short_epg':{'epg_listings':[{'title':base64.b64encode(b'Programme').decode(),'description':base64.b64encode(b'Description').decode(),'start':'10:00','end':'11:00'}]}
            }.get(action,{})
            body=json.dumps(data).encode()
        else:self.send_response(404);self.end_headers();return
        self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
class LocalServer(ThreadingHTTPServer):
    def server_bind(self):
        TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]
server=LocalServer(('127.0.0.1',0),Handler)
Path(sys.argv[1]).write_text(str(server.server_port))
print('FIXTURE READY',server.server_port,flush=True)
server.serve_forever()
