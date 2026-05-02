import Link from "next/link";

export default function PrivacyPolicyPage() {
  return (
    <main className="mx-auto min-h-screen w-full max-w-3xl px-4 py-12">
      <h1 className="text-3xl font-bold text-slate-900">Privacy Policy</h1>
      <p className="mt-2 text-sm text-slate-500">Last updated: May 2, 2026</p>

      <div className="mt-8 space-y-6 text-sm leading-7 text-slate-700">
        <section>
          <h2 className="text-lg font-semibold text-slate-900">Overview</h2>
          <p className="mt-2">
            Jobtree is a hiring platform for salon owners and job seekers. This policy explains
            what information we collect, how we use it, and how we protect user data.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Information We Collect</h2>
          <p className="mt-2">
            We may collect phone number, profile details, job and application activity, and device
            information needed for login, notifications, and service reliability.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">How We Use Data</h2>
          <p className="mt-2">
            Data is used to provide authentication, match users with opportunities, enable hiring
            workflows, improve support, and maintain platform security.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Data Sharing</h2>
          <p className="mt-2">
            We do not sell personal data. We may share data with service providers (for example,
            cloud hosting, notifications, and communication providers) only as required to operate
            the platform.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900">Contact</h2>
          <p className="mt-2">
            For privacy questions or deletion requests, contact{" "}
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
