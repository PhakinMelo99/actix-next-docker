import TestClient from "./TestClient";

function txt(x: any){ return typeof x === "string" ? x : JSON.stringify(x, null, 2); }

export default async function Test() {
  const base = process.env.BACKEND_INTERNAL_URL || "http://backend-dev:8080";
  const jobs = [
    fetch(`${base}/api/hello?name=${encodeURIComponent("Dev")}`, { cache: "no-store" }).then(r=>r.text()),
    fetch(`${base}/api/add?a=7&b=35`, { cache: "no-store" }).then(r=>r.json()),
    fetch(`${base}/api/user/42`,      { cache: "no-store" }).then(r=>r.json()),
    fetch(`${base}/api/time`,         { cache: "no-store" }).then(r=>r.text()),
  ];

  const [hello, sum, user, time] = (await Promise.allSettled(jobs)).map(x =>
    x.status === "fulfilled" ? x.value : `ERR: ${(x as any).reason?.message ?? String((x as any).reason)}`
  );

  return (
    <main style={{padding:24, fontFamily:"system-ui"}}>
      <h2>/test — Server-side checks (safe)</h2>
      <pre>{txt(hello)}</pre>
      <pre>{txt(sum)}</pre>
      <pre>{txt(user)}</pre>
      <pre>{txt(time)}</pre>
      <hr style={{margin:"16px 0"}} />
      <TestClient />
    </main>
  );
}