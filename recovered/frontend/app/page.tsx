export default async function Home() {
  const base = process.env.BACKEND_INTERNAL_URL || "http://backend-dev:8080";
  let health = "(no reply)";
  try {
    const r = await fetch(`${base}/healthz`, { cache: "no-store" });
    health = r.ok ? await r.text() : `err ${r.status}`;
  } catch (e: any) {
    health = `error: ${e?.message ?? String(e)}`;
  }

  return (
    <main style={{padding:24, fontFamily:"system-ui"}}>
      <h1>Next + Actix Dev</h1>
      <p>Backend health: <code>{health}</code></p>
      <ul>
        <li><a href="/test">/test playground</a></li>
      </ul>
    </main>
  );
}