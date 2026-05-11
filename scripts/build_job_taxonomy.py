#!/usr/bin/env python3
"""Build assets/data/job_taxonomy.json — run from repo root: python3 scripts/build_job_taxonomy.py"""
from __future__ import annotations

import json
import re
from pathlib import Path


def slug(s: str) -> str:
    s = s.strip().lower()
    s = re.sub(r"[\s/,&]+", "_", s)
    s = re.sub(r"[^a-z0-9_]+", "", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s[:64] or "item"


def sub(en: str, hi: str) -> dict[str, str]:
    return {"id": slug(en), "labelEn": en.strip(), "labelHi": hi.strip() or en.strip()}


# --- General / artists (EN, HI) pairs; HI empty uses EN in UI ---
def C(cid: str, en: str, hi: str, pairs: list[tuple[str, str]]) -> dict:
    return {
        "id": cid,
        "labelEn": en,
        "labelHi": hi or en,
        "subcategories": [sub(a, b) for a, b in pairs],
    }


# Unisex Hairstylist — full list from spec (EN + HI)
UNISEX = C(
    "unisex_hairstylist",
    "Unisex Hairstylist",
    "यूनिसेक्स हेयरस्टाइलिस्ट",
    [
        ("2 Layers Cut", "लेयर्स कट करना"),
        ("3 Steps Cut", "स्टेप्स कट करना"),
        ("Bob Cut", "बॉब कट करना"),
        ("U-cut", "यू- कट करना"),
        ("V-cut", "वी- कट करना"),
        ("Feather Cut", "फ़ेदर कट करना"),
        ("Razor Cut", "रेज़र कट करना"),
        ("Fringes / Bangs", "फ्रिंजेज़ / बैंग्स"),
        ("Gents Fade Cut", "जेंट्स फेड कट करना"),
        ("Gents Taper Cut", "टेपर कट करना"),
        ("Undercuts", "अंडरकट्स करना"),
        ("Beard Trimming & Shaping", "दाढ़ी ट्रिमिंग और शेपिंग करना"),
        ("Blow-Drying", "ब्लो-ड्राईिंग करना"),
        ("Straightening & Curling", "स्ट्रेटनिंग और कर्लिंग करना"),
        ("Men's Hair Styling", "पुरुषों की हेयर स्टाइलिंग करना"),
        ("Global Colour & Root Touch-up", "ग्लोबल कलर और रूट टच-अप करना"),
        ("Highlights & Lowlights", "हाइलाइट्स और लो-लाइट्स करना"),
        ("Balayage", "बैलेयाज का नॉलेज"),
        ("Ombre", "ओम्ब्रे का नॉलेज"),
        ("Fashion Colours", "फैशन कलर्स का नॉलेज"),
        ("Toning & Colour Correction", "टोनिंग और कलर करेक्शन करना"),
        ("Smoothing & Straightening", "स्मूदनिंग और स्ट्रेटनिंग करना"),
        ("Keratin / Protein / Botox", "केराटिन / प्रोटीन / बोटॉक्स ट्रीटमेंट करना"),
        ("Hair Extensions", "हेयर एक्सटेंशंस का नॉलेज"),
        ("Perming", "पर्मिंग / कर्लिंग"),
        ("Hair spa", "हेयर स्पा करना"),
        ("Waxing", "वैक्सिंग करना"),
        ("Moustache Styling / Perming", "मूंछों की स्टाइलिंग / परमिंग करना"),
        ("Hair Wig / Patch Work", "हेयर विग / पैच वर्क का नॉलेज"),
        ("Dandruff & Hairfall Treatments", "डैंड्रफ और हेयरफॉल ट्रीटमेंट करना"),
        ("Manicure", "मैनीक्योर का नॉलेज"),
        ("Pedicure", "पेडीक्योर का नॉलेज"),
        ("Client Consultation", "क्लाइंट कंसल्टेशन करना"),
        ("Product knowledge", "प्रोडक्ट नॉलेज"),
        ("Salon Management", "सैलून मैनेज करना"),
        ("Professionalism", "काम के प्रति जिम्मेदारी"),
    ],
)

LADIES = C(
    "ladies_hairstylist",
    "Ladies Hairstylist",
    "लेडीज़ हेयरस्टाइलिस्ट",
    [
        ("Straight Cut", "स्ट्रेट कट करना"),
        ("U-cut", "यू- कट करना"),
        ("V-cut", "वी- कट करना"),
        ("Layer cut", "लेयर कट करना"),
        ("Step Cut", "स्टेप कट करना"),
        ("Feather Cut", "फ़ेदर कट करना"),
        ("Razor Cut", "रेज़र कट करना"),
        ("Fringes/Bangs", "फ्रिंजेज़ / बैंग्स"),
        ("Bob/Lob Cuts", "बॉब / लॉब कट्स करना"),
        ("Blow-Dry", "ब्लो-ड्राई करना"),
        ("Curls/Waves", "कर्ल्स / वेव्स"),
        ("Global Colour", "ग्लोबल कलर करना"),
        ("Highlights & Lowlights", "हाइलाइट्स और लो-लाइट्स का नॉलेज"),
        ("Balayage", "बैलेयाज का नॉलेज"),
        ("Ombre", "ओम्ब्रे का नॉलेज"),
        ("Fashion Colours", "फैशन कलर्स करना"),
        ("Colour Correction", "कलर करेक्शन करना"),
        ("Smoothing/Rebonding", "स्मूदनिंग / रीबॉन्डिंग करना"),
        ("Keratin/Botox Treatments", "केराटिन / बोटॉक्स ट्रीटमेंट्स करना"),
        ("Hair Extensions", "हेयर एक्सटेंशंस का नॉलेज"),
        ("Protein Treatment", "प्रोटीन ट्रीटमेंट करना"),
        ("Hair Spa", "हेयर स्पा करना"),
        ("Waxing", "वैक्सिंग करना"),
        ("Hair Wig", "हेयर विग का नॉलेज"),
        ("Dandruff & Hairfall Treatment", "डैंड्रफ और हेयरफॉल ट्रीटमेंट करना"),
        ("Manicure", "मैनीक्योर का नॉलेज"),
        ("Pedicure", "पेडीक्योर का नॉलेज"),
        ("Product Knowledge", "प्रोडक्ट नॉलेज"),
        ("Client Consultation", "क्लाइंट कंसल्टेशन करना"),
        ("Salon Management", "सैलून मैनेज करना"),
        ("Professionalism", "काम के प्रति जिम्मेदारी"),
    ],
)

GENTS = C(
    "gents_hairstylist",
    "Gents Hairstylist",
    "जेंट्स हेयरस्टाइलिस्ट",
    [
        ("Crew cut", "क्रू कट करना"),
        ("Buzz Cut", "बज कट करना"),
        ("Mullet Cut", "मुलेट कट करना"),
        ("Fade", "फ़ेड कट करना"),
        ("Taper", "टेपर कट करना"),
        ("Skin fade", "स्किन फ़ेड कट करना"),
        ("Undercut", "अंडरकट करना"),
        ("Pompadour", "पॉम्पाडोर कट करना"),
        ("Beard Setting", "बीयर्ड सेटिंग करना"),
        ("Moustache Styling/Perming", "मूंछ स्टाइलिंग / पर्मिंग करना"),
        ("Wax/Gel/Hair Spray Styling", "पुरुषों की वैक्स / जेल / हेयर स्प्रे स्टाइलिंग"),
        ("Global Hair Colour", "ग्लोबल हेयर कलर करना"),
        ("Highlights / Streaks", "हाइलाइट्स / स्ट्रिक्स करना"),
        ("Fashion Colours", "फ़ैशन कलर्स करना"),
        ("Smoothing/Rebonding", "स्मूदिंग / रीबॉन्डिंग करना"),
        ("Perming/Curling", "पर्मिंग / कर्लिंग करना"),
        ("Keratin", "केरेटिन करना"),
        ("Protein/Botox Treatment", "प्रोटीन / बोटॉक्स ट्रीटमेंट करना"),
        ("Hair Spa", "हेयर स्पा करना"),
        ("Manicure", "मैनीक्योर का नॉलेज"),
        ("Pedicure", "पेडीक्योर का नॉलेज"),
        ("Waxing", "वैक्सिंग करना"),
        ("Hair Wig / Patch Work", "हेयर विग / पैच वर्क का नॉलेज"),
        ("Client Consultation", "क्लाइंट कंसल्टेशन करना"),
        ("Salon Management", "सैलून मैनेज करना"),
        ("Professionalism", "काम के प्रति जिम्मेदारी"),
    ],
)

HAIR_COLOURIST = C(
    "hair_colourist",
    "Hair Colourist",
    "हेयर कलरिस्ट",
    [
        ("Global Hair Colour", "ग्लोबल हेयर कलर करना"),
        ("Grey Coverage", "ग्रे कवरेज करना"),
        ("Fashion Colour Application", "फैशन कलर अप्लिकेशन करना"),
        ("Foil Highlights", "हाइलाइट्स करना"),
        ("Lowlights", "लो-लाइट्स करना"),
        ("Streaks", "स्ट्रिक्स करना"),
        ("Baby Lights", "बेबी लाइट्स करना"),
        ("Balayage", "बैलेयाज का नॉलेज"),
        ("Ombre / Sombre", "ओम्ब्रे / सोम्ब्रे का नॉलेज"),
        ("Reverse Balayage", "रिवर्स बैलेयाज का नॉलेज"),
        ("Bleaching / Pre-Lightening", "ब्लिचिंग / प्री-लाइटनिंग करना"),
        ("Correct lift levels", "सही लिफ्ट लेवल्स प्राप्त करना"),
        ("Neutralizing brassiness", "ब्रासिनेस को न्यूट्रलाइज करना"),
        ("Fixing uneven colour", "अनियमित कलर ठीक करना"),
        ("Removing unwanted tones", "अनवांटेड टोन हटाना"),
        ("Dark-to-light & light-to-dark", "डार्क-टू-लाइट और लाइट-टू-डार्क करना"),
        ("Permanent / Semi-permanent colours", "पर्मानेंट और सेमी-पर्मानेंट कलर्स"),
        ("Client consultation", "क्लाइंट कंसल्टेशन करना"),
        ("Shade recommendation", "प्रोडक्ट नॉलेज"),
        ("Skin tone matching", "प्रोडक्ट नॉलेज"),
        ("Professionalism", "काम के प्रति जिम्मेदारी"),
        ("Salon management", "सैलून मैनेज करना"),
    ],
)


def T(en: str, hi: str = "") -> tuple[str, str]:
    return (en, hi)


def from_lines(cid: str, title_en: str, title_hi: str, lines: list[str]) -> dict:
    pairs: list[tuple[str, str]] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        pairs.append((line, ""))
    return C(cid, title_en, title_hi, pairs)


BEAUTICIAN = C(
    "beautician",
    "Beautician",
    "ब्यूटीशियन",
    [
        ("Cleanup", "क्लीनअप करना"),
        ("Basic Facial", "बेसिक फेशियल करना"),
        ("Advance Facial", "एडवांस फेशियल करना"),
        ("Skin analysis", "स्किन टाइप पहचान करना"),
        ("Waxing", "वैक्सिंग करना"),
        ("Rica/Liposhape Waxing", "रिका / लिपोशेप वैक्सिंग करना"),
        ("Threading", "थ्रेडिंग करना"),
        ("Manicure", "मैनीक्योर करना"),
        ("Pedicure", "पेडीक्योर करना"),
        ("Nail Filing & Polishing", "नेल फाइलिंग और पोलिशिंग करना"),
        ("Anti-Acne, Whitening & Anti-Ageing Treatments", "एंटी-एक्ने, व्हाइटनिंग और एंटी-एजिंग ट्रीटमेंट्स करना"),
        ("Body Polishing", "बॉडी पोलिशिंग करना"),
        ("Makeup (Basic)", "मेकअप (बेसिक) करना"),
        ("Makeup (Advance)", "मेकअप (एडवांस) करना"),
        ("Daily/Party Makeup", "डेली / पार्टी मेकअप करना"),
        ("3D Makeup", "3D मेकअप करना"),
        ("Airbrush", "एयरब्रश मेकअप करना"),
        ("Saree Draping", "साड़ी ड्रेपिंग करना"),
        ("Hairdos", "हेयरडोज़ करना"),
        ("Hair Extensions", "हेयर एक्सटेंशंस का नॉलेज"),
        ("Product Knowledge", "प्रोडक्ट नॉलेज"),
        ("Skin Consultation", ""),
        ("Hygiene & Safety", "हाइजीन और सेफ्टी का नॉलेज"),
        ("Professionalism", "काम के प्रति जिम्मेदारी"),
    ],
)

MAKEUP_ARTIST = from_lines(
    "makeup_artist",
    "Make Up Artist",
    "मेकअप आर्टिस्ट",
    [
        "Basic Makeup",
        "Advance Makeup",
        "Party Makeup",
        "Bridal Makeup",
        "HD Makeup",
        "Waterproof Makeup",
        "Long-Lasting Makeup",
        "Airbrush",
        "3D Makeup",
        "Celebrity & Fashion Makeup",
        "Natural, Glam, Matte, Dewy Looks",
        "Skin Prepping & Priming",
        "Colour Correction",
        "Eye Shadow Blending",
        "Eyeliner Styles",
        "Eyelash Application",
        "Threading",
        "Contour",
        "Blush",
        "Highlight",
        "Product Knowledge",
        "Hygiene & Safety",
        "Salon Management",
        "Professionalism",
    ],
)

SECTIONS = [
    {
        "id": "general",
        "labelEn": "General job type",
        "labelHi": "जनरल जॉब टाइप",
        "categories": [
            UNISEX,
            LADIES,
            GENTS,
            HAIR_COLOURIST,
            BEAUTICIAN,
            MAKEUP_ARTIST,
            from_lines("bridal_makeup_artist", "Bridal Makeup Artist", "ब्राइडल मेकअप आर्टिस्ट", [
                "HD Makeup", "Waterproof & long-lasting bridal makeup", "Traditional/Modern/Regional bridal looks",
                "Airbrush bridal makeup", "Colour correction", "Bridal eye makeup", "Eyelash application",
                "Perfect eyebrow shaping", "Bridal contour/highlight/blush", "Product knowledge", "Lip contouring",
                "Basic hair styling touch-ups", "Saree draping", "Hair extensions", "Hygiene & safety", "Professionalism",
            ]),
            from_lines("nail_artist", "Nail Artist", "नेल आर्टिस्ट", [
                "Nail cleaning, shaping & filing", "Nail buffing", "Freehand nail art", "Glitter, stones, chrome, foil, stickers",
                "Ombre & gradient effects", "3D nail art", "Acrylic extensions", "Gel extensions", "Polygel extensions",
                "French extensions", "Refill, repair & removal", "Gel polish UV/LED", "Classic/matte/chrome/French polish",
                "Nail shapes (coffin, almond, stiletto, square, ballerina)", "Top/base coats, gels, acrylics knowledge", "Professionalism",
            ]),
            from_lines("mehandi_artist", "Mehandi Artist", "मेहंदी आर्टिस्ट", [
                "Traditional designs", "Arabic designs", "Indian designs", "Rajasthani designs", "Contemporary designs",
                "Intricate patterns & customized design", "Glitter, stone & coloured mehandi", "Bridal mehandi specialization",
            ]),
            from_lines("tattoo_artist", "Tattoo Artist", "टैटू आर्टिस्ट", [
                "Lining", "Shading", "Coloring", "Traditional style", "Realism style", "Geometric style", "Tribal style",
                "Minimalistic style", "Freehand drawing", "Custom tattoo designs", "Colour theory & ink mixing",
                "Hygiene & safety", "Latest tattoo trends",
            ]),
            from_lines("hair_ritual_expert", "Hair Ritual Expert", "हेयर रिचुअल एक्सपर्ट", [
                "Scalp condition identification", "Hair types", "Deep conditioning rituals", "Keratin, botox & smoothing rituals",
                "Hair spa", "Hot oil & aromatherapy scalp rituals", "Pressure points", "Product knowledge", "Professional brands",
                "Hygiene & safety", "Client consultation", "Home care recommendations", "Professionalism",
            ]),
            from_lines("sfx_artist", "SFX Artist", "SFX आर्टिस्ट", [
                "Prosthetic application", "Fake wounds, scars, burns & bruises", "3D makeup & sculpting", "Airbrushing",
                "Blood effects & texture", "Colour mixing", "Lighting & camera impact", "Hygiene & safety",
            ]),
            from_lines("celebrity_hairstylist", "Celebrity Hairstylist", "सेलेब्रिटी हेयरस्टाइलिस्ट", [
                "Advanced haircutting", "Advanced styling", "Highlights", "Balayage", "Colour correction", "Hair extensions",
                "Wigs", "Latest hair trends", "Red-carpet styles", "Blow-drying", "Curling", "Straightening", "Updos",
                "Trend-setting hairstyles", "Premium products", "Collaboration with MUA/stylists/photographers",
            ]),
            from_lines("aromatherapy_specialist", "Aromatherapy Specialist", "अरोमाथेरेपी स्पेशलिस्ट", [
                "Essential oil knowledge", "Safe blending", "Body systems basics", "Client assessment", "Personalized plans",
                "Custom blends & diffuser recipes", "Dilution & safety", "Massage/inhalation/compress/bath/diffuser use",
                "Contraindications", "Calming environment", "Holistic wellness", "Documentation",
            ]),
            from_lines("wellness_consultant", "Wellness Consultant", "वेलनेस कंसल्टेंट", [
                "Holistic health knowledge", "Lifestyle evaluation", "Customized wellness programs", "Goal setting & tracking",
                "Stress & lifestyle management", "Basic nutrition", "Supportive behaviour", "Client records",
                "Educate on healthy living", "Spa/salon wellness services", "Recommend products/services",
            ]),
            from_lines("dermat_clinic_assistant", "Dermat Clinic Assistant", "डर्माट क्लिनिक असिस्टेंट", [
                "Assisting dermatologist", "Preparing rooms & tools", "Minor procedure assistance", "Sterilization & hygiene",
                "Managing appointments", "Patient history", "Laser/microderm/peels/LED basics", "Wood's lamp",
                "Numbing & skin prep", "Records & files", "Billing & clinic software", "Common skin conditions", "Product knowledge",
                "Patient counseling",
            ]),
            from_lines("hair_patch_artist", "Hair Patch Artist", "हेयर पैच आर्टिस्ट", [
                "Bald area measurement & mapping", "Patch cutting, blending & styling", "Glue/tape/clip fixing",
                "Patch maintenance", "Product & patch knowledge", "Client consultation", "Explaining patch types", "Daily care advice",
            ]),
            from_lines("aesthetician", "Aesthetician / Esthetician", "एस्थेटिशियन", [
                "Advanced facials", "Chemical peels", "Microdermabrasion", "Hydrafacial", "Dermaplaning", "Microneedling",
                "Acne & pigmentation", "Skin type identification", "Laser hair reduction", "Laser toning", "Photo facials",
                "RF skin tightening", "LED therapy", "Waxing", "Product knowledge", "Hygiene & safety", "Professionalism",
            ]),
            from_lines("manicurist_pedicurist", "Manicurist / Pedicurist", "मैनीक्योरिस्ट / पेडीक्योरिस्ट", [
                "Nail trimming, shaping & buffing", "Cuticle care", "Hand & foot exfoliation", "Manicure", "Pedicure",
                "Spa manicure & pedicure", "Tan removal", "Callus removal", "Hand massage", "Foot & lower-leg massage",
                "Smooth polish", "French polish", "Gel polish", "Hygiene & safety", "Product knowledge", "Professionalism",
            ]),
        ],
    }
]


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "assets" / "data" / "job_taxonomy.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    sec = SECTIONS[0]["categories"]
    fm = C(
        "freelance_makeup_artist",
        "Freelance Makeup Artist",
        "Freelance Makeup Artist",
        [(s["labelEn"], s.get("labelHi") or s["labelEn"]) for s in MAKEUP_ARTIST["subcategories"]]
        + [("Open to travel", "Open to travel")],
    )
    sec.append(fm)

    fh = C(
        "freelance_hairstylist",
        "Freelance Hairstylist",
        "फ्रीलांस हेयरस्टाइलिस्ट",
        [
            ("Women haircutting", "महिलाओं के हेयरकटिंग"),
            ("Men's haircutting", "पुरुषों के हेयरकटिंग"),
            ("Styling", "स्टाइलिंग की नॉलेज"),
            ("Blow-drying", "ब्लो-ड्राइंग की नॉलेज"),
            ("Basic to advanced hair colouring", "बेसिक से एडवांस हेयर कलरिंग की नॉलेज"),
            ("Bridal, party & event hairstyles", "ब्राइडल, पार्टी और इवेंट-आधारित हेयरस्टाइल बनाने की क्षमता"),
            ("Hair care products & treatments", "हेयर केयर प्रोडक्ट्स और ट्रीटमेंट की नॉलेज"),
            ("Strong client communication", "अच्छी कम्यूनिकेशन स्किल"),
            ("Open to travel", "Open to travel"),
        ],
    )
    sec.append(fh)

    fn = from_lines(
        "freelance_nail_artist",
        "Freelance Nail Artist",
        "Freelance नेल आर्टिस्ट",
        [
            "Nail cleaning, shaping & filing", "Cuticle care & buffing", "Freehand nail art",
            "Glitter, stones, chrome, foil, stickers", "Ombre & gradient", "3D nail art", "Acrylic/gel extensions",
            "Polygel extensions", "French extensions", "Refill, repair & removal", "Gel polish UV/LED",
            "Classic/matte/chrome/French polish", "Nail shapes", "Top/base/gels/acrylics knowledge", "Open to travel",
        ],
    )
    sec.append(fn)

    # --- Support & operations ---
    support = {
        "id": "support_operations",
        "labelEn": "Support & operations",
        "labelHi": "सपोर्ट और संचालन",
        "categories": [
            from_lines("salon_helper_housekeeping", "Salon Helper / Housekeeping", "सैलून हेल्पर / हाउसकीपिंग", [
                "Salon floor & stations cleaning", "Washrooms & reception cleanliness", "Assisting stylists & therapists",
                "Setting up stations", "Towel & laundry", "Water/tea service", "Organizing shelves", "Neat appearance",
            ]),
            from_lines("sweeper", "Sweeper", "स्वीपर", [
                "Removing hair, dust & waste", "Sweeping & mopping", "Wiping mirrors & counters", "Chairs & stations clean",
                "Emptying bins", "Waste segregation", "Washroom cleanliness", "Neat appearance",
            ]),
            from_lines("shampoo_boy", "Shampoo Boy", "शैम्पू बॉय", [
                "Proper shampooing", "Gentle scalp massage", "Preparing client for services", "Assisting stylists",
                "Shampoo knowledge", "Personal hygiene", "Towels & laundry",
            ]),
            from_lines("pantry_boy", "Pantry Boy", "पेंट्री बॉय", [
                "Tea, coffee & beverages", "Serving water & refreshments", "Pantry cleanliness", "Small errands",
            ]),
            from_lines("front_desk_receptionist", "Front Desk / Receptionist", "फ्रंट डेस्क / रिसेप्शनिस्ट", [
                "Greeting clients", "Understanding needs & guiding", "Scheduling & rescheduling", "Walk-ins & wait times",
                "Coordinating with staff", "Bookings & queries", "Bills & payments", "Client records", "Daily register",
                "Salon services knowledge", "Grooming", "Basic computer skills", "WhatsApp/SMS/email",
            ]),
            from_lines("salon_manager", "Salon Manager", "सैलून मैनेजर", [
                "Daily operations", "Staff schedules", "Queries & complaints", "Service quality", "Client retention",
                "Supervising team", "Training & motivation", "Team meetings", "Targets", "Upselling & retail",
                "Offers & promotions", "Cash register & closing", "Stock & wastage", "Safety protocols", "Reporting",
                "Performance tracking", "Communication skills", "Problem-solving", "Professional appearance",
            ]),
            from_lines("assistant_salon_manager", "Assistant Salon Manager", "असिस्टेंट सैलून मैनेजर", [
                "Assist manager daily", "Walk-ins & appointments", "Greeting clients", "Complaints",
                "Client satisfaction", "Training newcomers", "Service quality monitoring", "Promotions", "Targets",
                "Product displays", "Billing & payments", "Appointments & follow-ups", "Records", "Stock checks",
                "Salon cleanliness", "Communication & grooming", "Basic problem-solving",
            ]),
            from_lines("salon_supervisor", "Salon Supervisor", "सैलून सुपरवाइज़र", [
                "Day-to-day activities", "Service monitoring", "Staff coordination", "Greeting clients", "Stock monitoring",
                "Reporting to manager", "Grooming",
            ]),
            from_lines("guest_relations_executive", "Guest Relations Executive", "गेस्ट रिलेशंस एग्ज़िक्यूटिव", [
                "Welcoming clients", "Refreshments & comfort", "Professional attitude", "Understanding needs", "VIP care",
                "Communication", "Listening to concerns", "Escalation", "Waiting time", "Offers & memberships", "Grooming",
                "Appointment help", "Billing support",
            ]),
            from_lines("cashier_billing_executive", "Cashier / Billing Executive", "कैशियर / बिलिंग एग्ज़िक्यूटिव", [
                "Generating bills", "Cash & payments", "Daily register", "Billing software", "Greeting at counter",
                "Manager coordination", "Grooming", "Appointments",
            ]),
            from_lines("sales_executive", "Sales Executive", "सेल्स एग्ज़िक्यूटिव", [
                "Lead generation", "Product/service knowledge", "CRM", "Communication", "Sales reporting", "Coordination",
                "Market understanding", "Basic admin",
            ]),
        ],
    }

    academy = {
        "id": "academy",
        "labelEn": "Academy",
        "labelHi": "अकादमी",
        "categories": [
            from_lines("academy_head", "Academy Head", "एकेडमी हेड", [
                "Academic & operational leadership", "Curriculum & training quality", "Faculty management",
                "Student experience", "Admissions & marketing", "Quality & compliance", "Planning & reporting",
                "Industry & placement", "Report management",
            ]),
            from_lines("academy_manager", "Academy Manager", "एकेडमी मैनेजर", [
                "Academic leadership", "Training quality", "Faculty", "Student experience", "Admissions & marketing",
                "Compliance", "Reporting", "Placement coordination",
            ]),
            from_lines("academy_assistant_manager", "Academy Assistant Manager", "एकेडमी असिस्टेंट मैनेजर", [
                "Academic coordination", "Student management", "Trainer support", "Admin & ops", "Sales & admissions help",
                "Reporting & documentation", "Customer service", "Events & workshops",
            ]),
            from_lines("academy_supervisor", "Academy Supervisor", "Academy supervisor", [
                "Daily academic coordination", "Classroom management", "Student monitoring", "Admin support",
                "Quality & hygiene", "Assist head/manager", "Internal communication", "Events & workshops",
            ]),
            from_lines("academy_executive", "Academy Executive", "एकेडमी एग्ज़िक्यूटिव", [
                "Daily academic coordination", "Classroom management", "Student support", "Admin support",
                "Quality & hygiene", "Assist head/manager", "Notices & communication", "Events & workshops",
            ]),
        ],
    }

    creative = {
        "id": "creative_leadership",
        "labelEn": "Creative & education leadership",
        "labelHi": "क्रिएटिव और शिक्षा नेतृत्व",
        "categories": [
            from_lines("creative_head", "Creative Head (Hair/Makeup/Beauty)", "क्रिएटिव हेड (हेयर/मेकअप/ब्यूटी)", [
                "Advanced techniques", "Trend-setting looks", "Products & tools", "Artistic vision", "Team mentoring",
                "Creative projects", "Collaboration", "Client communication", "Trend forecasting", "Time & resource management",
            ]),
            from_lines("creative_director", "Creative Director", "क्रिएटिव डायरेक्टर", [
                "Artistic vision", "Trends & colour theory", "Campaigns & photoshoots", "Leading teams",
                "Project planning", "Creative decisions", "Communication", "Trend forecasting", "Collaboration",
            ]),
            from_lines("education_director", "Education Director", "एजुकेशन डायरेक्टर", [
                "Deep domain knowledge", "Training programs & curriculum", "Mentoring trainers", "Educational strategy",
                "Training monitoring", "Communication", "Trend awareness", "Collaboration",
            ]),
            from_lines("technical_director_hair", "Technical Director - Hair", "टेक्निकल डायरेक्टर - हेयर", [
                "Advanced haircutting/colouring/styling/treatments", "Hair textures & techniques", "Standard procedures",
                "Mentoring stylists", "Skill workshops", "Problem solving", "Global trends", "Creative collaboration",
            ]),
        ],
    }

    technician = {
        "id": "technician",
        "labelEn": "Technician",
        "labelHi": "टेक्नीशियन",
        "categories": [
            from_lines("beauty_technician", "Beauty Technician", "ब्यूटी टेक्नीशियन", [
                "Clean-up", "Basic & advance facials", "Bleach", "De-tan", "Skin analysis", "Waxing", "Threading",
                "Manicure & pedicure", "Nail shaping & polish", "Daily & party makeup", "Advance & 3D & HD makeup",
                "Airbrush", "Saree draping", "Hairdos", "Extensions", "Body scrub/polish", "Consultation",
                "Product knowledge", "Hygiene & safety", "Professionalism",
            ]),
            from_lines("colour_technician", "Colour Technician", "कलर टेक्निशियन", [
                "Root touch-ups", "Global colour", "Grey coverage", "Highlights & lowlights", "Balayage", "Ombré",
                "Colour melting", "Foiling", "Slicing", "Weaving", "Freehand", "Chemical knowledge", "Consultation",
                "Colour correction", "Safety & hygiene", "Products & tools", "Blow-drying",
            ]),
            from_lines("nail_technician", "Nail Technician", "नेल टेक्निशियन", [
                "Manicure", "Pedicure", "Shaping", "Cuticle work", "Buffing", "Prep", "Gel polish", "French", "Chrome",
                "Ombré", "Nail art basics", "Extensions", "Infills", "Refills", "Hygiene", "Glitter/stones/patterns",
            ]),
            from_lines("lash_technician", "Lash Technician", "लैश टेक्निशियन", [
                "Extensions classic/hybrid/volume", "Mapping", "Isolation", "Placement", "Curls/lengths/diameter",
                "Lash lifts", "Tinting", "Refills", "Safety", "Client handling", "Appointments",
            ]),
            from_lines("laser_technician", "Laser Technician", "लेज़र टेक्नीशियन", [
                "Laser machines knowledge", "Hair reduction safely", "Fitzpatrick scale", "Parameters", "Pre/post care",
                "Equipment maintenance", "Contraindications", "Patch testing", "Burns/pigmentation knowledge",
                "Consultation", "Records", "SOPs",
            ]),
            from_lines("chemical_peel_technician", "Chemical Peel Technician", "केमिकल पील टेक्नीशियन", [
                "Skin analysis & consultation", "AHA/BHA/TCA/enzyme peels", "Peel strengths", "Correct peel selection",
                "Skin prep", "Monitoring reactions", "Safety & hygiene", "Patch testing", "Aftercare", "Product suggestions",
                "Managing reactions", "Records",
            ]),
        ],
    }

    therapist = {
        "id": "therapist",
        "labelEn": "Therapist",
        "labelHi": "थैरेपिस्ट",
        "categories": [
            from_lines("beauty_therapist", "Beauty Therapist", "ब्यूटी थेरेपिस्ट", [
                "Basic & advance facials", "Skin analysis", "Clean-ups", "Body polishing", "Relaxing massage", "Waxing",
                "Threading", "Manicure & pedicure", "Spa", "Basic & advance & 3D & HD makeup", "Airbrush", "Hairdos",
                "Extensions", "Consultation", "Hygiene & safety", "Professionalism",
            ]),
            from_lines("skin_clinic_therapist", "Skin Clinic Therapist", "स्किन क्लिनिक थैरेपिस्ट", [
                "Consultation", "Deep cleansing facials", "Chemical peels", "Hydrafacial", "Advance facial",
                "Acne facials", "Anti-aging", "Microdermabrasion", "Microneedling", "High-frequency/ultrasonic/LED",
                "Laser hair reduction assist", "Hygiene", "Products", "Clinical assist", "Follow-ups", "Records", "Stock",
            ]),
            from_lines("hair_spa_therapist", "Hair Spa Therapist", "हेयर स्पा थैरेपिस्ट", [
                "Hydration spa", "Anti-dandruff", "Keratin spa", "Repair spa", "Smoothening spa", "Scalp detox",
                "Scalp analysis", "Pressure points", "Spa machines", "Custom solutions", "Product knowledge",
            ]),
            from_lines("body_spa_therapist", "Body Spa Therapist", "बॉडी स्पा थैरेपिस्ट", [
                "Swedish", "Deep tissue", "Aromatherapy", "Balinese", "Scrubs, wraps, steam & sauna", "Pressure & strokes",
                "Oils & blends", "Hygiene", "Privacy", "Professional empathy",
            ]),
            from_lines("reflexology_therapist", "Reflexology Therapist", "रिफ्लेक्सोलॉजी थैरेपिस्ट", [
                "Reflex zones", "Pressure-point techniques", "Foot/hand massage", "Tension relief", "Pressure rhythm",
                "Relaxing environment", "Hygiene", "Basic aromatherapy oils",
            ]),
        ],
    }

    educator = {
        "id": "educator",
        "labelEn": "Educator",
        "labelHi": "एजुकेटर",
        "categories": [
            from_lines("beauty_educator", "Beauty Educator", "ब्यूटी एजुकेटर", [
                "Skin theory & practical", "Beauty theory & practical", "Makeup", "Facials", "Clean-ups", "Bleaching",
                "Threading", "Waxing", "Mani/pedi", "Skin types", "Products", "Beauty science", "Tests & practical exams",
                "Student performance", "Hygiene standards", "Communication", "Course materials", "Professional behaviour",
            ]),
            from_lines("makeup_educator", "Makeup Educator", "मेकअप एजुकेटर", [
                "Training skills", "Basic & advance makeup", "Demonstrations", "Lesson plans", "Day/evening/party/HD/airbrush/bridal/editorial",
                "Colour theory", "Face shapes", "Tools & blending", "Student guidance", "Practical exams",
                "Brand knowledge", "Hygiene", "Presentation", "Global trends", "Professionalism",
            ]),
            from_lines("nail_educator", "Nail Educator", "Nail educator", [
                "Nail anatomy", "Mani/pedi techniques", "Extensions", "Gel/acrylic", "Nail art", "Trends", "Products",
                "Teaching skills", "Lesson plans", "Communication", "Workshops", "Documentation", "Records", "Collaboration",
            ]),
            from_lines("hair_educator", "Hair Educator", "हेयर एजुकेटर", [
                "Cutting, layering, texturizing", "Colour, highlights, balayage, ombré", "Fashion shades", "Smoothing & straightening",
                "Keratin & perming", "Hair science", "Scalp knowledge", "Blow-dry, curls, updos", "Men's grooming",
                "Teaching", "Communication", "Industry knowledge", "Trends", "Hygiene", "Records",
            ]),
            from_lines("skin_educator", "Skin Educator", "स्किन एजुकेटर", [
                "Skin anatomy", "Facials advance", "Peels, microderm, dermaplaning, hydrafacial, LED", "Teaching", "Brands",
                "Trends", "Hygiene", "Client handling", "Communication", "Records", "Workshops", "Demos",
            ]),
            from_lines("lash_brow_educator", "Lash & Brow Educator", "लैश और ब्रो एजुकेटर", [
                "Anatomy & growth cycles", "Classic/hybrid/volume/mega", "Lash lifts & tinting", "Brow shaping & threading",
                "Brow lamination", "Henna brows", "Teaching", "Hygiene", "Products", "Communication", "Records", "Workshops",
            ]),
        ],
    }

    trainer = {
        "id": "trainer",
        "labelEn": "Trainer",
        "labelHi": "ट्रेनर",
        "categories": [
            from_lines("makeup_trainer", "Makeup Trainer", "मेकअप ट्रेनर", [
                "Basic/party/bridal/HD/waterproof/long-lasting/airbrush/3D/celebrity looks", "Skin prep & priming",
                "Colour correction", "Eye shadow & eyeliner", "Strip lashes", "Threading", "Contour/blush/highlight",
                "Baking & setting", "Extensions", "Products", "Hygiene & tools", "Trends", "Communication",
            ]),
            from_lines("nail_trainer", "Nail Trainer", "नेल ट्रेनर", [
                "Nail service proficiency", "Mani/pedi/prep", "Gel polish", "Extensions & refills", "Shapes & filing",
                "Live demos", "Hands-on supervision", "Communication", "Records",
            ]),
            from_lines("body_spa_trainer", "Body Spa Trainer", "बॉडी स्पा ट्रेनर", [
                "Swedish, deep tissue, Balinese, aromatherapy, hot stone", "Polishing & wraps", "Pressure & strokes",
                "Relaxation", "Equipment", "Hygiene", "Teaching client handling",
            ]),
        ],
    }

    # Legacy quick-pick aliases (map to taxonomy for skills UI); subs optional
    legacy = {
        "id": "legacy_quick_roles",
        "labelEn": "Common roles (quick)",
        "labelHi": "आम रोल (जल्दी)",
        "categories": [
            C("hair_stylist", "Hair stylist (legacy)", "हेयर स्टाइलिस्ट", [("General hair services", "हेयर सर्विस")]),
            C("massage_therapist", "Massage therapist (legacy)", "मसाज थेरेपिस्ट", [("Body massage", "बॉडी मसाज")]),
            C("receptionist", "Receptionist (legacy)", "रिसेप्शनिस्ट", [("Front desk duties", "फ्रंट डेस्क")]),
            C("helper", "Helper (legacy)", "हेल्पर", [("Salon support", "सहायता")]),
            C("manager", "Manager (legacy)", "मैनेजर", [("Team management", "टीम प्रबंधन")]),
            C("other", "Other (custom title)", "अन्य", [("Custom duties as discussed", "कस्टम")]),
        ],
    }

    doc = {"version": 2, "sections": [SECTIONS[0], support, academy, creative, technician, therapist, educator, trainer, legacy]}
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Wrote", out, "sections", len(doc["sections"]))


if __name__ == "__main__":
    main()
