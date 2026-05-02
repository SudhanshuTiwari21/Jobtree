import type { Metadata } from "next";
import { DM_Sans } from "next/font/google";
import "./globals.css";

const dm = DM_Sans({
  subsets: ["latin"],
  variable: "--font-dm",
});

export const metadata: Metadata = {
  title: "Jobtree | Salon Hiring Platform",
  description:
    "Jobtree helps salon owners hire faster and job seekers find better opportunities.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${dm.variable} font-sans ${dm.className}`}>
        {children}
      </body>
    </html>
  );
}
