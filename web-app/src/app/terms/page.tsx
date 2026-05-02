import Link from "next/link";

export default function TermsPage() {
  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl px-4 py-12">
      <h1 className="text-3xl font-bold text-slate-900">Terms of Service</h1>
      <p className="mt-2 text-sm text-slate-500">Last updated: May 2, 2026</p>

      <div className="mt-8 space-y-6 text-sm leading-7 text-slate-700">
        <section>
          <h2 className="text-lg font-semibold text-slate-900">Acceptance</h2>
          <p className="mt-2">
            By using Jobtree, you agree to these terms and all applicable laws and regulations.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Platform Use</h2>
          <p className="mt-2">
            Users must provide accurate information, use the platform lawfully, and avoid misuse,
            fraud, or attempts to disrupt service operations.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Accounts and Security</h2>
          <p className="mt-2">
            Users are responsible for maintaining access to their verified phone number and for
            activity performed through their account.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Service Availability</h2>
          <p className="mt-2">
            Jobtree may update, suspend, or discontinue parts of the service to improve reliability
            and security.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Contact</h2>
          <p className="mt-2">
            For legal or service questions, contact{" "}
            <a className="font-medium text-[#3D3D7B] hover:underline" href="mailto:product@jobtree.org.in">
              product@jobtree.org.in
            </a>.
          </p>
        </section>
      </div>

      <div className="mt-10">
        <Link href="/" className="text-sm font-medium text-[#3D3D7B] hover:underline">
          Back to Home
        </Link>
      </div>
    </main>
  );
}
