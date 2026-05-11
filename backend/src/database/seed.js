import db from './connection.js';
import logger from '../utils/logger.js';

/**
 * Seed demo salon + active jobs in Noida for local/dev testing.
 * Idempotent: removes previous seed jobs for this salon in Noida, then re-inserts.
 *
 * Run: npm run db:seed  (from backend/, DATABASE_URL or DB_* must be set)
 */

const SEED_SALON_PHONE = '9999000001';

/** @type {Array<{ role: string; skills: string[]; numberOfStaff: number; salaryMin: number; salaryMax: number; workType: string; experience: string; description: string }>} */
const NOIDA_JOBS = [
  {
    role: 'unisex_hairstylist',
    skills: ['unisex_hairstylist/2_layers_cut', 'unisex_hairstylist/bob_cut', 'unisex_hairstylist/gents_fade_cut'],
    numberOfStaff: 2,
    salaryMin: 18000,
    salaryMax: 32000,
    workType: 'full_time',
    experience: 'fresher_ok',
    description: 'Busy Noida salon needs unisex stylists for cuts, fades, and styling.',
  },
  {
    role: 'ladies_hairstylist',
    skills: ['ladies_hairstylist/straight_cut', 'ladies_hairstylist/layer_cut', 'ladies_hairstylist/blowdry'],
    numberOfStaff: 1,
    salaryMin: 20000,
    salaryMax: 40000,
    workType: 'full_time',
    experience: 'experience_required',
    description: 'Looking for an experienced ladies hairstylist for Sector 18 branch.',
  },
  {
    role: 'beautician',
    skills: ['beautician/cleanup', 'beautician/basic_facial', 'beautician/waxing'],
    numberOfStaff: 2,
    salaryMin: 15000,
    salaryMax: 28000,
    workType: 'full_time',
    experience: 'fresher_ok',
    description: 'Beautician for facials, cleanup, and waxing — training can be provided.',
  },
  {
    role: 'makeup_artist',
    skills: ['makeup_artist/basic_makeup', 'makeup_artist/party_makeup', 'makeup_artist/hd_makeup'],
    numberOfStaff: 1,
    salaryMin: 22000,
    salaryMax: 45000,
    workType: 'full_time',
    experience: 'experience_required',
    description: 'Party and HD makeup artist for events and salon clients.',
  },
  {
    role: 'nail_artist',
    skills: ['nail_artist/nail_cleaning_shaping_filing', 'nail_artist/gel_polish_uv_led', 'nail_artist/freehand_nail_art'],
    numberOfStaff: 1,
    salaryMin: 16000,
    salaryMax: 30000,
    workType: 'part_time',
    experience: 'fresher_ok',
    description: 'Nail desk — gel polish, extensions, and nail art.',
  },
  {
    role: 'front_desk_receptionist',
    skills: ['front_desk_receptionist/greeting_clients', 'front_desk_receptionist/scheduling_rescheduling', 'front_desk_receptionist/bookings_queries'],
    numberOfStaff: 1,
    salaryMin: 14000,
    salaryMax: 22000,
    workType: 'full_time',
    experience: 'fresher_ok',
    description: 'Front desk: appointments, billing support, and client coordination.',
  },
  {
    role: 'hair_stylist',
    skills: ['hair_stylist/general_hair_services'],
    numberOfStaff: 2,
    salaryMin: 17000,
    salaryMax: 30000,
    workType: 'full_time',
    experience: 'fresher_ok',
    description: 'General hair stylist (legacy role) — cuts and basic services.',
  },
  {
    role: 'massage_therapist',
    skills: ['massage_therapist/body_massage'],
    numberOfStaff: 1,
    salaryMin: 19000,
    salaryMax: 35000,
    workType: 'full_time',
    experience: 'experience_required',
    description: 'Spa therapist for body massage (legacy role).',
  },
];

async function seedNoidaJobs() {
  const connected = await db.checkConnection();
  if (!connected.connected) {
    logger.error('Database not reachable. Set DATABASE_URL or DB_* in .env');
    process.exit(1);
  }

  await db.transaction(async (client) => {
    const salonRes = await client.query(
      `INSERT INTO salons (phone_number, country_code, salon_name, owner_name, city, profile_completion_percent)
       VALUES ($1, '+91', $2, $3, 'Noida', 55)
       ON CONFLICT (phone_number) DO UPDATE SET
         salon_name = EXCLUDED.salon_name,
         owner_name = EXCLUDED.owner_name,
         city = EXCLUDED.city
       RETURNING id`,
      [SEED_SALON_PHONE, 'Jobtree Demo Salon (Noida)', 'Seed Owner']
    );
    const salonId = salonRes.rows[0].id;

    const del = await client.query(
      `DELETE FROM jobs WHERE salon_id = $1 AND location ILIKE $2`,
      [salonId, '%Noida%']
    );
    logger.info(`Removed ${del.rowCount} existing seed Noida job(s) for demo salon.`);

    for (const j of NOIDA_JOBS) {
      await client.query(
        `INSERT INTO jobs (
          salon_id, job_role, other_category, custom_role_name, skills, location, number_of_staff,
          salary_min, salary_max, work_type, experience, accommodation, preferred_gender,
          status, completion_percent, description
        ) VALUES (
          $1, $2, NULL, NULL, $3::jsonb, 'Noida', $4,
          $5, $6, $7, $8, NULL, 'any',
          'active', 72, $9
        )`,
        [
          salonId,
          j.role,
          JSON.stringify(j.skills),
          j.numberOfStaff,
          j.salaryMin,
          j.salaryMax,
          j.workType,
          j.experience,
          j.description,
        ]
      );
    }

    logger.info(`Inserted ${NOIDA_JOBS.length} active jobs in Noida (salon phone ${SEED_SALON_PHONE}).`);
  });

  await db.closePool();
}

seedNoidaJobs().catch((err) => {
  logger.error('Seed failed:', err);
  process.exit(1);
});
