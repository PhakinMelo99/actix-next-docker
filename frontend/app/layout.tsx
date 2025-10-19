export const metadata = { title: "Next + Actix Dev" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body style={{fontFamily:"system-ui"}}>{children}</body></html>;
}