import Image from "next/image";
import Link from "next/link";

export default function HomePage() {
  return (
    <main className="relative overflow-hidden bg-slate-50 px-4 py-12 md:py-16">
      <div className="pointer-events-none absolute -top-32 left-1/2 h-80 w-80 -translate-x-1/2 rounded-full bg-[#7a7ac6]/20 blur-3xl" />
      <div className="pointer-events-none absolute -right-20 top-1/2 h-64 w-64 rounded-full bg-[#3D3D7B]/20 blur-3xl" />

      <section className="relative z-10 mx-auto w-full max-w-4xl rounded-3xl border border-slate-200 bg-white/90 p-7 shadow-xl backdrop-blur md:p-10">
        <div className="mb-8 flex flex-col items-start justify-between gap-6 sm:flex-row sm:items-center">
          <div className="flex items-center gap-3">
            <Image src="/logo.png" alt="Jobtree logo" width={220} height={74} priority />
          </div>
          <div className="inline-flex rounded-full border border-[#3D3D7B]/20 bg-[#3D3D7B]/5 px-4 py-2 text-xs font-semibold tracking-wide text-[#3D3D7B]">
            Official Website
          </div>
        </div>

        <h1 className="max-w-2xl text-3xl font-bold leading-tight text-slate-900 md:text-4xl">
          Hiring platform connecting salons with skilled beauty professionals.
        </h1>
        <p className="mt-4 max-w-2xl text-base text-slate-600 md:text-lg">
          Jobtree helps salon owners post jobs, manage candidates, and streamline hiring,
          while job seekers discover opportunities and apply in minutes.
        </p>

        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm font-semibold text-slate-900">For Salon Owners</p>
            <p className="mt-1 text-sm text-slate-600">
              Post openings, review applicants, and manage hiring pipeline.
            </p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm font-semibold text-slate-900">For Job Seekers</p>
            <p className="mt-1 text-sm text-slate-600">
              Explore salon jobs, apply quickly, and track application updates.
            </p>
          </div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <p className="text-sm font-semibold text-slate-900">Secure & Reliable</p>
            <p className="mt-1 text-sm text-slate-600">
              OTP login, cloud backend, notifications, and media upload support.
            </p>
          </div>
        </div>

        <div className="mt-9 flex flex-wrap items-center gap-3">
          <Link
            href="/privacy-policy"
            className="rounded-xl bg-[#3D3D7B] px-5 py-3 text-sm font-semibold text-white transition hover:bg-[#333366]"
          >
            Privacy Policy
          </Link>
          <Link
            href="/terms"
            className="rounded-xl border border-slate-300 bg-white px-5 py-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-100"
          >
            Terms of Service
          </Link>
        </div>

        <div className="mt-10 border-t border-slate-200 pt-6 text-sm text-slate-600">
          <p>
            Organization:{" "}
            <span className="font-medium text-slate-800">
              JOBTREE TECHNOLOGIES PRIVATE LIMITED
            </span>
          </p>
          <p className="mt-1">
            Contact:{" "}
            <a
              href="mailto:product@jobtree.org.in"
              className="font-medium text-[#3D3D7B] hover:underline"
            >
              product@jobtree.org.in
            </a>
          </p>
          <p className="mt-1 text-xs text-slate-500">
            This website is maintained for product information and app verification purposes.
          </p>
        </div>
      </section>
    </main>
  );
}
