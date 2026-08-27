import json,socket,sys,time
def call(cmd, params=None, timeout=25):
    s=socket.create_connection(("127.0.0.1",3768),timeout=timeout)
    s.sendall((json.dumps({"command":cmd,"params":params or {}})+"\n").encode())
    buf=b""
    while b"\n" not in buf:
        c=s.recv(1<<20)
        if not c: break
        buf+=c
    s.close()
    return json.loads(buf.decode().splitlines()[0]) if buf else {}
if __name__=="__main__":
    cmd=sys.argv[1]; params=json.loads(sys.argv[2]) if len(sys.argv)>2 else {}
    print(json.dumps(call(cmd,params))[:3000])
