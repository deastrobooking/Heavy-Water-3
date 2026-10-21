// SPDX-FileCopyrightText: © 2026 Jeffrey C. Ollie <jeff@ocjtech.us>
// SPDX-License-Identifier: MIT

//! The ID3v1 genre list.
//!
//! ID3v1 stores a genre as a single byte indexing this list.  Entries 0 to 79
//! are from the original ID3v1 specification and 80 to 191 are the extensions
//! Winamp added, which every tagger since has followed.
//!
//! The names are display strings and the several projects that carry this
//! list disagree on their spelling -- "Jazz-Funk" against "Jazz+Funk",
//! "Britpop" against "BritPop", and so on.  These follow TagLib, and were
//! checked against Mutagen's copy: the two agree on the length and on 181 of
//! the 192 entries, and every disagreement is one of those spellings.  The
//! exception is entry 133, whose name in the original Winamp list is a racial
//! slur; both projects replace it, and the replacement here is TagLib's.

/// Genre names by ID3v1 genre byte.  A byte of 192 or more names no genre.
pub const names = [192][]const u8{
    "Blues",             "Classic Rock",          "Country",
    "Dance",             "Disco",                 "Funk",
    "Grunge",            "Hip-Hop",               "Jazz",
    "Metal",             "New Age",               "Oldies",
    "Other",             "Pop",                   "R&B",
    "Rap",               "Reggae",                "Rock",
    "Techno",            "Industrial",            "Alternative",
    "Ska",               "Death Metal",           "Pranks",
    "Soundtrack",        "Euro-Techno",           "Ambient",
    "Trip-Hop",          "Vocal",                 "Jazz-Funk",
    "Fusion",            "Trance",                "Classical",
    "Instrumental",      "Acid",                  "House",
    "Game",              "Sound Clip",            "Gospel",
    "Noise",             "Alternative Rock",      "Bass",
    "Soul",              "Punk",                  "Space",
    "Meditative",        "Instrumental Pop",      "Instrumental Rock",
    "Ethnic",            "Gothic",                "Darkwave",
    "Techno-Industrial", "Electronic",            "Pop-Folk",
    "Eurodance",         "Dream",                 "Southern Rock",
    "Comedy",            "Cult",                  "Gangsta",
    "Top 40",            "Christian Rap",         "Pop/Funk",
    "Jungle",            "Native American",       "Cabaret",
    "New Wave",          "Psychedelic",           "Rave",
    "Showtunes",         "Trailer",               "Lo-Fi",
    "Tribal",            "Acid Punk",             "Acid Jazz",
    "Polka",             "Retro",                 "Musical",
    "Rock & Roll",       "Hard Rock",             "Folk",
    "Folk Rock",         "National Folk",         "Swing",
    "Fast Fusion",       "Bebop",                 "Latin",
    "Revival",           "Celtic",                "Bluegrass",
    "Avant-garde",       "Gothic Rock",           "Progressive Rock",
    "Psychedelic Rock",  "Symphonic Rock",        "Slow Rock",
    "Big Band",          "Chorus",                "Easy Listening",
    "Acoustic",          "Humour",                "Speech",
    "Chanson",           "Opera",                 "Chamber Music",
    "Sonata",            "Symphony",              "Booty Bass",
    "Primus",            "Porn Groove",           "Satire",
    "Slow Jam",          "Club",                  "Tango",
    "Samba",             "Folklore",              "Ballad",
    "Power Ballad",      "Rhythmic Soul",         "Freestyle",
    "Duet",              "Punk Rock",             "Drum Solo",
    "A Cappella",        "Euro-House",            "Dancehall",
    "Goa",               "Drum & Bass",           "Club-House",
    "Hardcore Techno",   "Terror",                "Indie",
    "Britpop",           "Worldbeat",             "Polsk Punk",
    "Beat",              "Christian Gangsta Rap", "Heavy Metal",
    "Black Metal",       "Crossover",             "Contemporary Christian",
    "Christian Rock",    "Merengue",              "Salsa",
    "Thrash Metal",      "Anime",                 "Jpop",
    "Synthpop",          "Abstract",              "Art Rock",
    "Baroque",           "Bhangra",               "Big Beat",
    "Breakbeat",         "Chillout",              "Downtempo",
    "Dub",               "EBM",                   "Eclectic",
    "Electro",           "Electroclash",          "Emo",
    "Experimental",      "Garage",                "Global",
    "IDM",               "Illbient",              "Industro-Goth",
    "Jam Band",          "Krautrock",             "Leftfield",
    "Lounge",            "Math Rock",             "New Romantic",
    "Nu-Breakz",         "Post-Punk",             "Post-Rock",
    "Psytrance",         "Shoegaze",              "Space Rock",
    "Trop Rock",         "World Music",           "Neoclassical",
    "Audiobook",         "Audio Theatre",         "Neue Deutsche Welle",
    "Podcast",           "Indie Rock",            "G-Funk",
    "Dubstep",           "Garage Rock",           "Psybient",
};

/// The name for an ID3v1 genre byte, or null if it names none.
pub fn name(index: u8) ?[]const u8 {
    return if (index < names.len) names[index] else null;
}
