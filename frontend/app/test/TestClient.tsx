"use client";
import { useRef, useState } from "react";

async function fetchWithRetry(url: string, init?: RequestInit, tries = 3, delay = 400): Promise<Response> {
  let e: any;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, init);
      if (r.ok) return r;
      if (r.status >= 500) throw new Error("server " + r.status);
      return r;
    } catch (err) {
      e = err;
      await new Promise(res => setTimeout(res, delay * Math.pow(2, i)));
    }
  }
  throw e ?? new Error("fail");
}

export default function TestClient(){
  const [name, setName] = useState("Phakin");
  const [log, setLog]  = useState<string>("");
  const esRef = useRef<EventSource | null>(null);

  const logAdd = (s: string) => setLog(prev => (prev + "\n" + s).slice(-6000));

  async function call(path: string, init?: RequestInit){
    const r = await fetch(path, init);
    const text = await r.text();
    logAdd(`GET ${path} -> ${r.status} ${text}`);
  }

  return (
    <section style={{marginTop:24}}>
      <h3>Client Playground (via Next proxy /api/backend/*)</h3>

      <div style={{display:"grid", gap:8, gridTemplateColumns:"repeat(auto-fit,minmax(220px,1fr))"}}>
        <div style={{border:"1px solid #eee", padding:8, borderRadius:8}}>
          <b>Basics</b><br/>
          <div style={{display:"flex", gap:8, alignItems:"center"}}>
            <label>Name:</label>
            <input value={name} onChange={e=>setName(e.target.value)} style={{padding:6, border:"1px solid #ccc"}} />
          </div>
          <button onClick={()=>call(`/api/backend/api/hello?name=${encodeURIComponent(name)}`)}>Hello</button>
          <button onClick={()=>call(`/api/backend/api/add?a=10&b=25`)}>Add 10+25</button>
          <button onClick={()=>call(`/api/backend/api/user/7`)}>User #7</button>
          <button onClick={()=>call(`/api/backend/api/time`)}>Time</button>
        </div>

        <div style={{border:"1px solid #eee", padding:8, borderRadius:8}}>
          <b>POST</b><br/>
          <button onClick={()=>fetch(`/api/backend/api/echo`, {method:"POST", body:`ECHO from ${new Date().toISOString()}`})
              .then(r=>r.text()).then(t=>logAdd(t))}>POST Echo (text)</button>
          <button onClick={()=>fetch(`/api/backend/api/json`, {
              method:"POST",
              headers:{ "Content-Type":"application/json" },
              body: JSON.stringify({ message:"hi", tags:["a","b"], urgent:true })
            }).then(r=>r.json()).then(j=>logAdd(JSON.stringify(j,null,2)))}>POST JSON</button>
        </div>

        <div style={{border:"1px solid #eee", padding:8, borderRadius:8}}>
          <b>Resilience</b><br/>
          <button onClick={()=>fetchWithRetry(`/api/backend/api/flaky`).then(r=>r.text()).then(t=>logAdd("flaky:"+t)).catch(e=>logAdd("flaky fail:"+e))}>Flaky (retry x3)</button>
          <button onClick={()=>{
            const ac = new AbortController();
            setTimeout(()=>ac.abort(), 800);
            fetch(`/api/backend/api/slow?ms=2000`, { signal: ac.signal })
              .then(r=>r.text()).then(t=>logAdd("slow:"+t)).catch(e=>logAdd("slow aborted:"+e));
          }}>Slow + Abort@800ms</button>
          <button onClick={()=>Promise.all([...Array(15)].map((_,i)=>fetch(`/api/backend/api/hello?name=${i}`)))
            .then(async rs=>{
              const codes = await Promise.all(rs.map(r=>r.text().then(t=>`${r.status}:${t}`)));
              logAdd("Burst 15 -> "+codes.join(", "));
            })}>Burst (show 429)</button>
        </div>

        <div style={{border:"1px solid #eee", padding:8, borderRadius:8}}>
          <b>Secure (x-api-key)</b><br/>
          <button onClick={()=>fetch(`/api/backend/api/secure/ping`, { headers:{ "x-api-key":"dev123" } })
            .then(r=>r.text()).then(t=>logAdd("secure ok:"+t))}>Secure Ping (OK)</button>
          <button onClick={()=>fetch(`/api/backend/api/secure/ping`)
            .then(r=>r.text()).then(t=>logAdd("secure no-key:"+t))}>Secure Ping (No Key -&gt; 401)</button>
        </div>

        <div style={{border:"1px solid #eee", padding:8, borderRadius:8}}>
          <b>Streaming</b><br/>
          <button onClick={()=>fetch(`/api/backend/api/bytes?kb=256`)
            .then(r=>r.blob()).then(b=>logAdd(`downloaded ${b.size} bytes`))}>Download 256KB</button>
          <div style={{display:"flex", gap:8, marginTop:8}}>
            <button onClick={()=>{
              if (esRef.current) esRef.current.close();
              esRef.current = new EventSource(`/api/backend/api/sse`);
              setLog("SSE: connecting...");
              esRef.current.onmessage = (ev)=> logAdd(ev.data);
              (esRef.current as any).addEventListener("tick", (ev: MessageEvent)=> logAdd("[tick] "+ev.data));
              esRef.current.onerror = ()=> logAdd("SSE error");
            }}>SSE Start</button>
            <button onClick={()=>{ esRef.current?.close(); esRef.current = null; setLog("SSE closed"); }}>SSE Stop</button>
          </div>
        </div>
      </div>

      <pre style={{whiteSpace:"pre-wrap", marginTop:12, padding:8, border:"1px solid #eee", minHeight:140}}>{log}</pre>
    </section>
  );
}