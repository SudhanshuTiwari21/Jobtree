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


def _skill_key(en: str) -> str:
    return re.sub(r"\s+", " ", en.strip().lower())


# Full-phrase Hindi labels (checked before auto-translation).
SKILL_PHRASE_HI: dict[str, str] = {
    _skill_key(k): v
    for k, v in {
        # Sweeper / housekeeping
        "Removing hair, dust & waste": "बाल, धूल और कचरा हटाना",
        "Sweeping & mopping": "झाड़ू और पोछा लगाना",
        "Wiping mirrors & counters": "शीशे और काउंटर पोछना",
        "Chairs & stations clean": "कुर्सी और स्टेशन साफ करना",
        "Emptying bins": "डस्टबिन खाली करना",
        "Waste segregation": "कचरा अलग करना",
        "Washroom cleanliness": "वॉशरूम की सफाई",
        "Neat appearance": "साफ-सुथरा रूप",
        # Salon helper
        "Salon floor & stations cleaning": "सैलून फ्लोर और स्टेशन की सफाई",
        "Washrooms & reception cleanliness": "वॉशरूम और रिसेप्शन की सफाई",
        "Assisting stylists & therapists": "स्टाइलिस्ट और थेरेपिस्ट की सहायता",
        "Setting up stations": "स्टेशन तैयार करना",
        "Towel & laundry": "तौलिए और लॉन्ड्री",
        "Water/tea service": "पानी/चाय सर्विस",
        "Organizing shelves": "शेल्फ़ व्यवस्थित करना",
        # Shampoo / pantry
        "Proper shampooing": "सही तरीके से शैम्पू करना",
        "Gentle scalp massage": "हल्की सिर की मालिश",
        "Preparing client for services": "क्लाइंट को सर्विस के लिए तैयार करना",
        "Assisting stylists": "स्टाइलिस्ट की सहायता",
        "Shampoo knowledge": "शैम्पू का नॉलेज",
        "Personal hygiene": "व्यक्तिगत हाइजीन",
        "Towels & laundry": "तौलिए और लॉन्ड्री",
        "Tea, coffee & beverages": "चाय, कॉफी और पेय",
        "Serving water & refreshments": "पानी और रिफ्रेशमेंट सर्व करना",
        "Pantry cleanliness": "पेंट्री की सफाई",
        "Small errands": "छोटे-मोटे काम",
        # Reception / front desk
        "Greeting clients": "क्लाइंट का स्वागत करना",
        "Understanding needs & guiding": "ज़रूरत समझकर गाइड करना",
        "Scheduling & rescheduling": "अपॉइंटमेंट शेड्यूल और रीशेड्यूल",
        "Walk-ins & wait times": "वॉक-इन और वेटिंग टाइम",
        "Coordinating with staff": "स्टाफ के साथ समन्वय",
        "Bookings & queries": "बुकिंग और सवाल-जवाब",
        "Bills & payments": "बिल और पेमेंट",
        "Client records": "क्लाइंट रिकॉर्ड",
        "Daily register": "दैनिक रजिस्टर",
        "Salon services knowledge": "सैलून सर्विसेज का नॉलेज",
        "Grooming": "ग्रूमिंग",
        "Basic computer skills": "बेसिक कंप्यूटर स्किल्स",
        "WhatsApp/SMS/email": "व्हाट्सऐप/एसएमएस/ईमेल",
        # Makeup artist
        "Basic Makeup": "बेसिक मेकअप करना",
        "Advance Makeup": "एडवांस मेकअप करना",
        "Party Makeup": "पार्टी मेकअप करना",
        "Bridal Makeup": "ब्राइडल मेकअप करना",
        "HD Makeup": "एचडी मेकअप करना",
        "Waterproof Makeup": "वॉटरप्रूफ मेकअप करना",
        "Long-Lasting Makeup": "लॉन्ग-लास्टिंग मेकअप करना",
        "Celebrity & Fashion Makeup": "सेलेब्रिटी और फैशन मेकअप",
        "Natural, Glam, Matte, Dewy Looks": "नेचुरल, ग्लैम, मैट, ड्यू लुक",
        "Skin Prepping & Priming": "स्किन प्रिपिंग और प्राइमिंग",
        "Colour Correction": "कलर करेक्शन",
        "Eye Shadow Blending": "आई शैडो ब्लेंडिंग",
        "Eyeliner Styles": "आईलाइनर स्टाइल",
        "Eyelash Application": "आईलैश लगाना",
        "Contour": "कॉन्टूर करना",
        "Blush": "ब्लश लगाना",
        "Highlight": "हाइलाइट करना",
        "Salon Management": "सैलून मैनेजमेंट का नॉलेज",
        # Mehandi
        "Traditional designs": "ट्रेडिशनल डिज़ाइन",
        "Arabic designs": "अरबी डिज़ाइन",
        "Indian designs": "भारतीय डिज़ाइन",
        "Rajasthani designs": "राजस्थानी डिज़ाइन",
        "Contemporary designs": "कंटेम्पररी डिज़ाइन",
        "Intricate patterns & customized design": "जटिल पैटर्न और कस्टम डिज़ाइन",
        "Glitter, stone & coloured mehandi": "ग्लिटर, स्टोन और कलर्ड मेहंदी",
        "Bridal mehandi specialization": "ब्राइडल मेहंदी स्पेशलाइज़ेशन",
        # Tattoo
        "Lining": "लाइनिंग",
        "Shading": "शेडिंग",
        "Coloring": "कलरिंग",
        "Traditional style": "ट्रेडिशनल स्टाइल",
        "Realism style": "रियलिज़्म स्टाइल",
        "Geometric style": "ज्योमेट्रिक स्टाइल",
        "Tribal style": "ट्राइबल स्टाइल",
        "Minimalistic style": "मिनिमलिस्टिक स्टाइल",
        "Freehand drawing": "फ्रीहैंड ड्रॉइंग",
        "Custom tattoo designs": "कस्टम टैटू डिज़ाइन",
        "Colour theory & ink mixing": "कलर थ्योरी और इंक मिक्सिंग",
        "Latest tattoo trends": "लेटेस्ट टैटू ट्रेंड्स",
        # Academy
        "Academic & operational leadership": "एकेडमिक और ऑपरेशनल लीडरशिप",
        "Curriculum & training quality": "करिकुलम और ट्रेनिंग क्वालिटी",
        "Faculty management": "फैकल्टी मैनेजमेंट",
        "Student experience": "स्टूडेंट एक्सपीरियंस",
        "Admissions & marketing": "एडमिशंस और मार्केटिंग",
        "Quality & compliance": "क्वालिटी और कम्प्लायंस",
        "Planning & reporting": "प्लानिंग और रिपोर्टिंग",
        "Industry & placement": "इंडस्ट्री और प्लेसमेंट",
        "Report management": "रिपोर्ट मैनेजमेंट",
    }.items()
}


def _has_latin_word(s: str) -> bool:
    return bool(re.search(r"[A-Za-z]{3,}", s))


# Transliterate leftover English tokens to Devanagari (hinglish salon terms).
_LATIN_TO_HI: dict[str, str] = {
    "lip": "लिप", "contouring": "कॉन्टूरिंग", "saree": "साड़ी", "draping": "ड्रेपिंग",
    "shapes": "शेप्स", "coffin": "कॉफिन", "almond": "आलमंड", "stiletto": "स्टिलेटो",
    "square": "स्क्वेयर", "ballerina": "बैलेरिना", "top": "टॉप", "base": "बेस",
    "coats": "कोट्स", "coat": "कोट", "acrylics": "एक्रिलिक", "acrylic": "एक्रिलिक",
    "condition": "कंडीशन", "identification": "पहचान", "types": "टाइप्स", "type": "टाइप",
    "deep": "डीप", "conditioning": "कंडीशनिंग", "rituals": "रिचुअल", "ritual": "रिचुअल",
    "keratin": "केराटिन", "botox": "बोटॉक्स", "smoothing": "स्मूदिंग", "hot": "हॉट",
    "points": "पॉइंट्स", "point": "पॉइंट", "professional": "प्रोफेशनल", "brands": "ब्रांड्स",
    "brand": "ब्रांड", "home": "होम", "care": "केयर", "recommendations": "सलाह",
    "recommendation": "सलाह", "prosthetic": "प्रोस्थेटिक", "application": "अप्लाई",
    "fake": "फेक", "wounds": "घाव", "wound": "घाव", "scars": "निशान", "scar": "निशान",
    "burns": "जलन", "bruises": "चोट", "sculpting": "स्कल्प्टिंग", "airbrushing": "एयरब्रशिंग",
    "blood": "ब्लड", "effects": "इफेक्ट्स", "effect": "इफेक्ट", "texture": "टेक्सचर",
    "mixing": "मिक्सिंग", "lighting": "लाइटिंग", "camera": "कैमरा", "impact": "इम्पैक्ट",
    "haircutting": "हेयरकटिंग", "styling": "स्टाइलिंग", "wigs": "विग", "wig": "विग",
    "latest": "लेटेस्ट", "red-carpet": "रेड-कार्पेट", "styles": "स्टाइल", "blow-drying": "ब्लो-ड्राईंग",
    "blow": "ब्लो", "drying": "ड्राईंग", "curling": "कर्लिंग", "straightening": "स्ट्रेटनिंग",
    "updos": "अपडो", "trend-setting": "ट्रेंड-सेटिंग", "hairstyles": "हेयरस्टाइल",
    "hairstyle": "हेयरस्टाइल", "premium": "प्रीमियम", "collaboration": "कोलैबोरेशन",
    "photographers": "फोटोग्राफर्स", "photographer": "फोटोग्राफर", "essential": "एसेंशियल",
    "blending": "ब्लेंडिंग", "systems": "सिस्टम", "basics": "बेसिक्स", "assessment": "असेसमेंट",
    "personalized": "पर्सनलाइज़्ड", "plans": "प्लान", "plan": "प्लान", "custom": "कस्टम",
    "blends": "ब्लेंड", "diffuser": "डिफ्यूज़र", "recipes": "रेसिपी", "dilution": "डिल्यूशन",
    "massage": "मसाज", "inhalation": "इनहेलेशन", "compress": "कंप्रेस", "bath": "बाथ",
    "contraindications": "कॉन्ट्राइंडिकेशन", "calming": "काम", "environment": "माहौल",
    "holistic": "होलिस्टिक", "wellness": "वेलनेस", "documentation": "डॉक्यूमेंटेशन",
    "health": "हेल्थ", "lifestyle": "लाइफस्टाइल", "evaluation": "इवैल्यूएशन",
    "customized": "कस्टमाइज़्ड", "programs": "प्रोग्राम", "program": "प्रोग्राम",
    "goal": "गोल", "tracking": "ट्रैकिंग", "stress": "स्ट्रेस", "nutrition": "न्यूट्रिशन",
    "supportive": "सपोर्टिव", "behaviour": "व्यवहार", "educate": "सिखाना", "healthy": "स्वस्थ",
    "living": "जीवन", "recommend": "सुझाव", "services": "सर्विसेज", "service": "सर्विस",
    "dermatologist": "डर्मेटोलॉजिस्ट", "preparing": "तैयारी", "rooms": "कमरे", "room": "कमरा",
    "tools": "टूल्स", "tool": "टूल", "minor": "माइनर", "procedure": "प्रोसीजर",
    "assistance": "सहायता", "sterilization": "स्टेरलाइज़ेशन", "managing": "मैनेज", "patient": "मरीज़",
    "history": "हिस्ट्री", "microderm": "माइक्रोडर्म", "basics": "बेसिक्स", "numbing": "नंबिंग",
    "prep": "प्रेप", "files": "फाइलें", "file": "फाइल", "billing": "बिलिंग", "clinic": "क्लिनिक",
    "software": "सॉफ्टवेयर", "common": "कॉमन", "conditions": "कंडीशन", "counseling": "काउंसलिंग",
    "bald": "गंजा", "area": "एरिया", "measurement": "माप", "mapping": "मैपिंग",
    "patch": "पैच", "cutting": "कटिंग", "glue": "ग्लू", "tape": "टेप", "clip": "क्लिप",
    "fixing": "फिक्सिंग", "maintenance": "मेंटेनेंस", "explaining": "समझाना", "advice": "सलाह",
    "daily": "दैनिक", "chemical": "केमिकल", "microdermabrasion": "माइक्रोडर्माब्रेशन",
    "hydrafacial": "हाइड्राफेशियल", "dermaplaning": "डर्माप्लानिंग", "microneedling": "माइक्रोनीडलिंग",
    "acne": "एक्ने", "pigmentation": "पिग्मेंटेशन", "toning": "टोनिंग", "photo": "फोटो",
    "tightening": "टाइटनिंग", "therapy": "थेरेपी", "trimming": "ट्रिमिंग", "cuticle": "क्यूटिकल",
    "exfoliation": "एक्सफोलिएशन", "hand": "हाथ", "foot": "पैर", "tan": "टैन", "callus": "कैलस",
    "lower-leg": "निचला पैर", "smooth": "स्मूद", "french": "फ्रेंच", "gel": "जेल",
    "operations": "ऑपरेशंस", "operation": "ऑपरेशन", "schedules": "शेड्यूल", "schedule": "शेड्यूल",
    "complaints": "शिकायत", "retention": "रिटेंशन", "team": "टीम", "meetings": "मीटिंग",
    "offers": "ऑफर", "cash": "कैश", "safety": "सेफ्टी", "communication": "कम्युनिकेशन",
    "skills": "स्किल्स", "skill": "स्किल", "walk-ins": "वॉक-इन", "walk-in": "वॉक-इन",
    "newcomers": "नए लोग", "newcomer": "नया", "monitoring": "मॉनिटरिंग", "displays": "डिस्प्ले",
    "display": "डिस्प्ले", "checks": "चेक", "check": "चेक", "vip": "वीआईपी", "attitude": "रवैया",
    "escalation": "एस्केलेशन", "counter": "काउंटर", "lead": "लीड", "generation": "जनरेशन",
    "crm": "सीआरएम", "market": "मार्केट", "admin": "एडमिन", "open": "ओपन", "travel": "ट्रैवल",
    "shampoo": "शैम्पू", "boy": "बॉय", "pantry": "पेंट्री", "errands": "काम", "beverages": "पेय",
    "serving": "सर्व", "refreshments": "रिफ्रेशमेंट", "scalp": "स्कैल्प", "gentle": "हल्की",
    "proper": "सही", "laundry": "लॉन्ड्री", "shelves": "शेल्फ़", "shelf": "शेल्फ़",
    "floor": "फ्लोर", "reception": "रिसेप्शन", "queries": "सवाल", "query": "सवाल",
    "whatsapp": "व्हाट्सऐप", "sms": "एसएमएस", "email": "ईमेल", "computer": "कंप्यूटर",
    "understanding": "समझ", "guiding": "गाइड", "guide": "गाइड", "needs": "ज़रूरत",
    "wait": "वेट", "times": "टाइम", "time": "समय",
    "gels": "जेल", "oil": "ऑयल", "aromatherapy": "अरोमाथेरेपी", "pressure": "प्रेशर",
    "trend": "ट्रेंड", "trend-setting": "ट्रेंड-सेटिंग", "with": "के साथ", "mua": "एमयूए",
    "stylists": "स्टाइलिस्ट", "safe": "सेफ", "body": "बॉडी", "client": "क्लाइंट",
    "salon": "सैलून", "spa": "स्पा", "wood": "वुड", "lamp": "लैंप", "wood's": "वुड्स",
    "product": "प्रोडक्ट", "reduction": "रिडक्शन", "gradient": "ग्रेडिएंट", "staff": "स्टाफ",
    "sales": "सेल्स", "executive": "एग्ज़िक्यूटिव", "cashier": "कैशियर", "guest": "गेस्ट",
    "relations": "रिलेशंस", "supervisor": "सुपरवाइज़र", "assistant": "असिस्टेंट",
    "manager": "मैनेजर", "front": "फ्रंट", "desk": "डेस्क", "receptionist": "रिसेप्शनिस्ट",
    "shampoo": "शैम्पू", "pantry": "पेंट्री", "sweeper": "स्वीपर", "helper": "हेल्पर",
    "housekeeping": "हाउसकीपिंग", "inventory": "इन्वेंटरी", "merchandising": "मर्चेंडाइज़िंग",
    "forecasting": "फोरकास्टिंग", "budgeting": "बजटिंग", "payroll": "पेरोल",
    "recruitment": "भर्ती", "onboarding": "ऑनबोर्डिंग", "exit": "एग्ज़िट", "interviews": "इंटरव्यू",
    "interview": "इंटरव्यू", "hiring": "हायरिंग", "firing": "फायरिंग", "incentives": "इंसेंटिव",
    "leave": "लीव", "policies": "पॉलिसी", "policy": "पॉलिसी", "audit": "ऑडिट", "audits": "ऑडिट",
    "mystery": "मिस्ट्री", "shopping": "शॉपिंग", "feedback": "फीडबैक", "reviews": "रिव्यू",
    "review": "रिव्यू", "ratings": "रेटिंग", "rating": "रेटिंग", "google": "गूगल",
    "social": "सोशल", "media": "मीडिया", "content": "कंटेंट", "influencer": "इन्फ्लुएंसर",
    "campaign": "कैंपेन", "campaigns": "कैंपेन", "events": "इवेंट", "event": "इवेंट",
    "workshop": "वर्कशॉप", "seminar": "सेमिनार", "webinar": "वेबिनार", "demo": "डेमो",
    "demos": "डेमो", "practical": "प्रैक्टिकल", "theory": "थ्योरी", "exam": "एग्ज़ाम",
    "exams": "एग्ज़ाम", "certificate": "सर्टिफिकेट", "certificates": "सर्टिफिकेट",
    "placement": "प्लेसमेंट", "internship": "इंटर्नशिप", "internships": "इंटर्नशिप",
}


def _devanagarize_remaining(hi: str) -> str:
    result = hi
    for eng, dev in sorted(_LATIN_TO_HI.items(), key=lambda x: -len(x[0])):
        result = re.sub(rf"\b{re.escape(eng)}\b", dev, result, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", result).strip()


def auto_hi_skill(en: str) -> str:
    """Generate Hindi skill label when no manual translation is provided."""
    en = en.strip()
    if not en:
        return en

    keyed = _skill_key(en)
    if keyed in SKILL_PHRASE_HI:
        return SKILL_PHRASE_HI[keyed]

    exact = {
        "Professionalism": "काम के प्रति जिम्मेदारी",
        "Hygiene & safety": "हाइजीन और सेफ्टी का नॉलेज",
        "Hygiene & Safety": "हाइजीन और सेफ्टी का नॉलेज",
        "Product knowledge": "प्रोडक्ट नॉलेज",
        "Product Knowledge": "प्रोडक्ट नॉलेज",
        "Client consultation": "क्लाइंट कंसल्टेशन करना",
        "Client Consultation": "क्लाइंट कंसल्टेशन करना",
        "Skin Consultation": "स्किन कंसल्टेशन का नॉलेज",
        "Open to travel": "ट्रैवल के लिए तैयार",
    }
    if en in exact:
        return exact[en]

    # Longest-first phrase replacements (English → Devanagari / hinglish terms)
    phrases = [
        ("Nail cleaning, shaping & filing", "नाखून की सफाई, शेपिंग और फाइलिंग"),
        ("Academic & operational leadership", "एकेडमिक और ऑपरेशनल लीडरशिप"),
        ("Curriculum & training quality", "करिकुलम और ट्रेनिंग क्वालिटी"),
        ("Admissions & marketing", "एडमिशंस और मार्केटिंग"),
        ("Quality & compliance", "क्वालिटी और कम्प्लायंस"),
        ("Planning & reporting", "प्लानिंग और रिपोर्टिंग"),
        ("Industry & placement", "इंडस्ट्री और प्लेसमेंट"),
        ("Basic & advance facials", "बेसिक और एडवांस फेशियल"),
        ("Manicure & pedicure", "मैनीक्योर और पेडीक्योर"),
        ("Daily & party makeup", "डेली और पार्टी मेकअप"),
        ("Highlights & lowlights", "हाइलाइट्स और लो-लाइट्स"),
        ("Root touch-ups", "रूट टच-अप"),
        ("Global colour", "ग्लोबल कलर"),
        ("Grey coverage", "ग्रे कवरेज"),
        ("Colour correction", "कलर करेक्शन"),
        ("Safety & hygiene", "सेफ्टी और हाइजीन"),
        ("Products & tools", "प्रोडक्ट्स और टूल्स"),
        ("Nail art basics", "नेल आर्ट बेसिक्स"),
        ("Freehand nail art", "फ्रीहैंड नेल आर्ट"),
        ("Glitter, stones, chrome, foil, stickers", "ग्लिटर, स्टोन्स, क्रोम, फॉइल, स्टिकर्स"),
        ("Ombre & gradient effects", "ओम्ब्रे और ग्रेडिएंट इफेक्ट्स"),
        ("3D nail art", "3D नेल आर्ट"),
        ("Acrylic extensions", "एक्रिलिक एक्सटेंशंस"),
        ("Gel extensions", "जेल एक्सटेंशंस"),
        ("Polygel extensions", "पॉलीजेल एक्सटेंशंस"),
        ("French extensions", "फ्रेंच एक्सटेंशंस"),
        ("Refill, repair & removal", "रिफिल, रिपेयर और रिमूवल"),
        ("Gel polish UV/LED", "जेल पॉलिश UV/LED"),
        ("Classic/matte/chrome/French polish", "क्लासिक/मैट/क्रोम/फ्रेंच पॉलिश"),
        ("Waterproof & long-lasting bridal makeup", "वॉटरप्रूफ और लॉन्ग-लास्टिंग ब्राइडल मेकअप"),
        ("Traditional/Modern/Regional bridal looks", "ट्रेडिशनल/मॉडर्न/रिजनल ब्राइडल लुक"),
        ("Airbrush bridal makeup", "एयरब्रश ब्राइडल मेकअप"),
        ("Bridal eye makeup", "ब्राइडल आई मेकअप"),
        ("Perfect eyebrow shaping", "परफेक्ट आईब्रो शेपिंग"),
        ("Bridal contour/highlight/blush", "ब्राइडल कॉन्टूर/हाइलाइट/ब्लश"),
        ("Basic hair styling touch-ups", "बेसिक हेयर स्टाइलिंग टच-अप"),
        ("Celebrity & Fashion Makeup", "सेलेब्रिटी और फैशन मेकअप"),
        ("Natural, Glam, Matte, Dewy Looks", "नेचुरल, ग्लैम, मैट, ड्यू लुक"),
        ("Skin Prepping & Priming", "स्किन प्रिपिंग और प्राइमिंग"),
        ("Eye Shadow Blending", "आई शैडो ब्लेंडिंग"),
        ("Eyeliner Styles", "आईलाइनर स्टाइल्स"),
        ("Eyelash Application", "आईलैश अप्लाई"),
        ("Faculty management", "फैकल्टी मैनेजमेंट"),
        ("Student experience", "स्टूडेंट एक्सपीरियंस"),
    ]
    result = en
    for eng, hi in sorted(phrases, key=lambda x: -len(x[0])):
        if eng.lower() in result.lower():
            result = re.sub(re.escape(eng), hi, result, flags=re.IGNORECASE)

    tokens = [
        ("professionalism", "काम के प्रति जिम्मेदारी"),
        ("consultation", "कंसल्टेशन"),
        ("management", "मैनेजमेंट"),
        ("knowledge", "नॉलेज"),
        ("training", "ट्रेनिंग"),
        ("teaching", "टीचिंग"),
        ("communication", "कम्युनिकेशन"),
        ("marketing", "मार्केटिंग"),
        ("admissions", "एडमिशंस"),
        ("faculty", "फैकल्टी"),
        ("student", "स्टूडेंट"),
        ("quality", "क्वालिटी"),
        ("compliance", "कम्प्लायंस"),
        ("planning", "प्लानिंग"),
        ("reporting", "रिपोर्टिंग"),
        ("industry", "इंडस्ट्री"),
        ("placement", "प्लेसमेंट"),
        ("leadership", "लीडरशिप"),
        ("curriculum", "करिकुलम"),
        ("operational", "ऑपरेशनल"),
        ("academic", "एकेडमिक"),
        ("makeup", "मेकअप"),
        ("bridal", "ब्राइडल"),
        ("party", "पार्टी"),
        ("advance", "एडवांस"),
        ("advanced", "एडवांस"),
        ("basic", "बेसिक"),
        ("facial", "फेशियल"),
        ("facials", "फेशियल"),
        ("waxing", "वैक्सिंग"),
        ("threading", "थ्रेडिंग"),
        ("manicure", "मैनीक्योर"),
        ("pedicure", "पेडीक्योर"),
        ("nail", "नेल"),
        ("hair", "हेयर"),
        ("skin", "स्किन"),
        ("colour", "कलर"),
        ("color", "कलर"),
        ("highlight", "हाइलाइट"),
        ("highlights", "हाइलाइट्स"),
        ("lowlights", "लो-लाइट्स"),
        ("balayage", "बैलेयाज"),
        ("ombre", "ओम्ब्रे"),
        ("ombré", "ओम्ब्रे"),
        ("airbrush", "एयरब्रश"),
        ("extensions", "एक्सटेंशंस"),
        ("hygiene", "हाइजीन"),
        ("safety", "सेफ्टी"),
        ("massage", "मसाज"),
        ("spa", "स्पा"),
        ("polish", "पॉलिश"),
        ("shaping", "शेपिंग"),
        ("filing", "फाइलिंग"),
        ("cleaning", "सफाई"),
        ("buffing", "बफिंग"),
        ("contour", "कॉन्टूर"),
        ("blush", "ब्लश"),
        ("eyeliner", "आईलाइनर"),
        ("eyelash", "आईलैश"),
        ("lashes", "लैश"),
        ("records", "रिकॉर्ड्स"),
        ("workshops", "वर्कशॉप"),
        ("demos", "डेमो"),
        ("trends", "ट्रेंड्स"),
        ("products", "प्रोडक्ट्स"),
        ("equipment", "इक्विपमेंट"),
        ("appointments", "अपॉइंटमेंट"),
        ("refills", "रिफिल"),
        ("refill", "रिफिल"),
        ("repair", "रिपेयर"),
        ("removal", "रिमूवल"),
        ("peels", "पील"),
        ("laser", "लेज़र"),
        ("therapy", "थेरेपी"),
        ("treatment", "ट्रीटमेंट"),
        ("treatments", "ट्रीटमेंट्स"),
        ("removing", "हटाना"),
        ("sweeping", "झाड़ू"),
        ("mopping", "पोछा"),
        ("wiping", "पोछना"),
        ("mirrors", "शीशे"),
        ("mirror", "शीशा"),
        ("counters", "काउंटर"),
        ("counter", "काउंटर"),
        ("chairs", "कुर्सी"),
        ("chair", "कुर्सी"),
        ("stations", "स्टेशन"),
        ("station", "स्टेशन"),
        ("emptying", "खाली करना"),
        ("bins", "डस्टबिन"),
        ("bin", "डस्टबिन"),
        ("waste", "कचरा"),
        ("segregation", "अलग करना"),
        ("washroom", "वॉशरूम"),
        ("washrooms", "वॉशरूम"),
        ("cleanliness", "सफाई"),
        ("neat", "साफ-सुथरा"),
        ("appearance", "रूप"),
        ("dust", "धूल"),
        ("assisting", "सहायता"),
        ("greeting", "स्वागत"),
        ("greeting", "स्वागत"),
        ("scheduling", "शेड्यूलिंग"),
        ("rescheduling", "रीशेड्यूल"),
        ("coordinating", "समन्वय"),
        ("bookings", "बुकिंग"),
        ("queries", "सवाल"),
        ("bills", "बिल"),
        ("payments", "पेमेंट"),
        ("register", "रजिस्टर"),
        ("grooming", "ग्रूमिंग"),
        ("supervising", "सुपरविज़न"),
        ("training", "ट्रेनिंग"),
        ("motivation", "प्रेरणा"),
        ("meetings", "मीटिंग"),
        ("targets", "टार्गेट"),
        ("upselling", "अपसेल"),
        ("retail", "रिटेल"),
        ("offers", "ऑफर"),
        ("promotions", "प्रमोशन"),
        ("closing", "क्लोज़िंग"),
        ("stock", "स्टॉक"),
        ("wastage", "वेस्टेज"),
        ("protocols", "प्रोटोकॉल"),
        ("performance", "परफॉर्मेंस"),
        ("tracking", "ट्रैकिंग"),
        ("problem", "समस्या"),
        ("solving", "सुलझाना"),
        ("welcoming", "स्वागत"),
        ("refreshments", "रिफ्रेशमेंट"),
        ("comfort", "आराम"),
        ("listening", "सुनना"),
        ("concerns", "चिंता"),
        ("escalation", "एस्केलेशन"),
        ("waiting", "वेटिंग"),
        ("memberships", "मेंबरशिप"),
        ("generating", "बनाना"),
        ("shampooing", "शैम्पू"),
        ("scalp", "स्कैल्प"),
        ("preparing", "तैयार करना"),
        ("organizing", "व्यवस्थित करना"),
        ("setting", "सेटअप"),
        ("laundry", "लॉन्ड्री"),
        ("towels", "तौलिए"),
        ("towel", "तौलिया"),
        ("shelves", "शेल्फ़"),
        ("floor", "फ्लोर"),
        ("reception", "रिसेप्शन"),
        ("designs", "डिज़ाइन"),
        ("design", "डिज़ाइन"),
        ("style", "स्टाइल"),
        ("drawing", "ड्रॉइंग"),
        ("lining", "लाइनिंग"),
        ("shading", "शेडिंग"),
        ("coloring", "कलरिंग"),
        ("traditional", "ट्रेडिशनल"),
        ("realism", "रियलिज़्म"),
        ("geometric", "ज्योमेट्रिक"),
        ("tribal", "ट्राइबल"),
        ("minimalistic", "मिनिमलिस्टिक"),
        ("freehand", "फ्रीहैंड"),
        ("customized", "कस्टम"),
        ("patterns", "पैटर्न"),
        ("intricate", "जटिल"),
        ("coloured", "कलर्ड"),
        ("specialization", "स्पेशलाइज़ेशन"),
        ("long-lasting", "लॉन्ग-लास्टिंग"),
        ("waterproof", "वॉटरप्रूफ"),
        ("contour", "कॉन्टूर"),
        ("blending", "ब्लेंडिंग"),
        ("prepping", "प्रिपिंग"),
        ("priming", "प्राइमिंग"),
        ("natural", "नेचुरल"),
        ("glam", "ग्लैम"),
        ("matte", "मैट"),
        ("dewy", "ड्यू"),
        ("looks", "लुक"),
        ("celebrity", "सेलेब्रिटी"),
        ("fashion", "फैशन"),
    ]
    result = result.replace(" & ", " और ").replace("&", " और ")
    for eng, hi in sorted(tokens, key=lambda x: -len(x[0])):
        result = re.sub(rf"\b{re.escape(eng)}\b", hi, result, flags=re.IGNORECASE)

    if keyed in SKILL_PHRASE_HI:
        return SKILL_PHRASE_HI[keyed]

    low = result.lower()
    knowledge_markers = (
        "नॉलेज", "management", "मैनेजमेंट", "knowledge", "consultation",
        "कंसल्टेशन", "awareness", "proficiency", "coordination", "reporting",
        "communication", "documentation", "records", "compliance", "strategy",
        "forecasting", "mentoring", "monitoring", "evaluation", "counseling",
        "experience", "leadership", "लीडरशिप", "products", "प्रोडक्ट",
        "equipment", "software", "trends", "understanding", "skills",
        "लीडरशिप", "मैनेजमेंट", "क्वालिटी", "कम्प्लायंस",
    )
    result = _devanagarize_remaining(result)
    if not _has_latin_word(result):
        return result
    if any(m in low for m in knowledge_markers):
        if not result.endswith("का नॉलेज") and not result.endswith("की नॉलेज"):
            return f"{result} का नॉलेज"
    if not result.endswith("करना") and not result.endswith("ना") and not result.endswith("नी"):
        return f"{result} करना"
    return _devanagarize_remaining(result)


def from_lines(cid: str, title_en: str, title_hi: str, lines: list[str]) -> dict:
    pairs: list[tuple[str, str]] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        pairs.append((line, auto_hi_skill(line)))
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
        ("Skin Consultation", "स्किन कंसल्टेशन का नॉलेज"),
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
    SWEEPER = C(
        "sweeper",
        "Sweeper",
        "स्वीपर",
        [
            ("Removing hair, dust & waste", "बाल, धूल और कचरा हटाना"),
            ("Sweeping & mopping", "झाड़ू और पोछा लगाना"),
            ("Wiping mirrors & counters", "शीशे और काउंटर पोछना"),
            ("Chairs & stations clean", "कुर्सी और स्टेशन साफ करना"),
            ("Emptying bins", "डस्टबिन खाली करना"),
            ("Waste segregation", "कचरा अलग करना"),
            ("Washroom cleanliness", "वॉशरूम की सफाई"),
            ("Neat appearance", "साफ-सुथरा रूप"),
        ],
    )
    SALON_HELPER = C(
        "salon_helper_housekeeping",
        "Salon Helper / Housekeeping",
        "सैलून हेल्पर / हाउसकीपिंग",
        [
            ("Salon floor & stations cleaning", "सैलून फ्लोर और स्टेशन की सफाई"),
            ("Washrooms & reception cleanliness", "वॉशरूम और रिसेप्शन की सफाई"),
            ("Assisting stylists & therapists", "स्टाइलिस्ट और थेरेपिस्ट की सहायता"),
            ("Setting up stations", "स्टेशन तैयार करना"),
            ("Towel & laundry", "तौलिए और लॉन्ड्री"),
            ("Water/tea service", "पानी/चाय सर्विस"),
            ("Organizing shelves", "शेल्फ़ व्यवस्थित करना"),
            ("Neat appearance", "साफ-सुथरा रूप"),
        ],
    )

    support = {
        "id": "support_operations",
        "labelEn": "Salon Management & Housekeeping",
        "labelHi": "सैलून मैनेजमेंट और हाउसकीपिंग",
        "categories": [
            SALON_HELPER,
            SWEEPER,
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
        "labelHi": "Academy",
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
            from_lines("academy_supervisor", "Academy Supervisor", "Academy Supervisor", [
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

    doc = {"version": 2, "sections": [SECTIONS[0], support, academy, creative, technician, therapist, educator, trainer]}
    # Final pass: ensure Hindi labels have no leftover English words
    for sec in doc["sections"]:
        for cat in sec["categories"]:
            for sub in cat["subcategories"]:
                en = sub["labelEn"]
                hi = sub.get("labelHi") or ""
                if _has_latin_word(hi):
                    sub["labelHi"] = auto_hi_skill(en)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Wrote", out, "sections", len(doc["sections"]))


if __name__ == "__main__":
    main()
