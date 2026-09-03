import json,os,socket,sys,time
# 3768 is the app's own default and stays the default here. LOGOS_INSPECTOR_PORT points a
# harness at a fixture it started itself, so a run cannot reach whatever else is on 3768.
PORT=int(os.environ.get("LOGOS_INSPECTOR_PORT","3768"))
def call(cmd, params=None, timeout=25):
    s=socket.create_connection(("127.0.0.1",PORT),timeout=timeout)
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
