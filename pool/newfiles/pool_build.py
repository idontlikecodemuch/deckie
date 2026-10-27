import json, os, re, csv, sys, hashlib, unicodedata, subprocess, statistics
sys.path.insert(0, "newfiles"); import finder
ROOT = finder.ROOT
discs = json.load(open("newfiles/discs_def.json")); final = {e["name"]: e for e in json.load(open("bpm_final.json"))}
lp = json.load(open("newfiles/library_probe.json")); newp = {p["file"]: p for p in json.load(open("newfiles/probe.json"))}
aub = json.load(open("newfiles/aubio.json")); items = json.load(open("shop/items.json"))
raw = {r["path"]: float(r["bpm_raw"]) for r in csv.DictReader(open("bpm_local.csv")) if r["bpm_raw"]}
def fold(s): return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c)).lower()
def mmss(s): return f"{int(s)//60}:{int(s)%60:02d}"
def hid(s): return hashlib.md5(s.encode()).hexdigest()[:10]
def era_of(y):
    try: y = int(str(y)[:4])
    except: return ""
    return "pre-90s" if y < 1990 else "90s" if y < 2000 else "2000s" if y < 2010 else "2010s" if y < 2020 else "2020s"
KEY_ERA = {"COLL":"90s","SUB":"90s","90S":"90s","F90":"90s","E90":"90s","00D":"2000s","00G":"2000s","10D":"2010s","HAL":"","PCA":"","PCK":"","PCM":"","TOP":"","MAY":"2020s","SCA":"2020s","ROB":"","SP":""}
KEY_LABEL = {"COLL":"Eurodance collection","SUB":"Eurodance collection","90S":"90s Hits 100","F90":"NOW Forever 90s","E90":"MoS Electronic 90s","00D":"2000s Dance Essentials","00G":"00s Greatest Hits","10D":"2010s Dance Essentials","HAL":"NOW Halloween","PCA":"old party CD (adult)","PCK":"old party CD (kids)","PCM":"old party CD (mixed)","TOP":"single in folder","MAY":"Gaga MAYHEM","SCA":"Doja Scarlet","ROB":"Robyn discography","SP":"NOW Summer Party 2024"}
def disc_of(bpm): return "F" if bpm and 118 <= bpm <= 135 else "R"
def fold_bpm(b):
    if not b: return None
    while b > 160: b /= 2
    while b < 68: b *= 2
    return round(b)

# ---------- hand decisions ----------
YEAR = {  # original release year for tracks whose source folder mixes eras
 "Bette Midler - I Put A Spell On You (Hocus Pocus)":1993,"Beyonce - Haunted":2013,"John Carpenter - Halloween Theme":1978,"Olivia Rodrigo - Vampire":2023,"Bobby Boris Pickett - Monster Mash":1962,"Doja Cat - Demons":2023,
 "The Specials - Ghost Town":1981,"Oingo Boingo - Dead Man's Party":1985,"The Cranberries - Zombie":1994,"The Citizens Of Halloween - This Is Halloween":1993,"DJ Jazzy Jeff & The Fresh Prince - A Nightmare On My Street":1988,
 "Meat Loaf - Bat Out Of Hell":1977,"Little Nell - Time Warp":1975,"Missy Elliott - Get Ur Freak On":2001,"Sugababes - Freak Like Me":2002,"Lady Gaga - Bloody Mary":2011,"Stevie Wonder - Superstition":1972,"Doja Cat - Paint The Town Red":2023,
 "Lady Gaga - Disease":2024,"P!nk - Funhouse":2008,"Warren Zevon - Werewolves Of London":1978,"Michael Jackson - Scream":1995,"Backstreet Boys - Everybody (Backstreet's Back)":1997,"Bow Wow Wow - I Want Candy":1982,"Little Mix - Black Magic":2015,
 "Tame Impala & Jennie - Dracula (Jennie Remix)":2025,"Ray Parker Jr. - Ghostbusters":1984,"Michael Jackson - Thriller":1982,"Lady Gaga - Bad Romance":2009,"Lady Gaga - Monster":2009,"Lady Gaga - Zombieboy":2025,"Talking Heads - Psycho Killer":1977,
 "Take That feat. Lulu - Relight My Fire":1993,"Rockwell - Somebody's Watching Me":1984,"Rihanna - Disturbia":2008,"Rob Zombie - Dragula":1998,"Electric Six - Danger! High Voltage":2003,"Lady Gaga - Abracadabra":2025,"Kylie vs New Order - Blue Monday Mashup":2002,
 "Beatfreakz - Somebody's Watching Me (2006)":2006,"Duran Duran - Hungry Like The Wolf":1982,"Taylor Swift - Look What You Made Me Do":2017,"Dead Or Alive - You Spin Me Round":1985,"The Trammps - Disco Inferno":1976,"Kesha - Cannibal":2010,
 "The Prodigy - Breathe":1996,"Depeche Mode - Personal Jesus":1989,"Yeah Yeah Yeahs - Heads Will Roll":2009,"Yeah Yeah Yeahs - Heads Will Roll (A-Trak Remix)":2009,"Britney Spears - Freakshow":2007,"Rick James - Super Freak":1981,"Rogue Traders - Voodoo Child":2005,
 "Ava Max - Sweet But Psycho":2018,"The Grid - Swamp Thing":1994,"Sash! - Mysterious Times":1998,"DJ Dado - X-Files":1996,"Cartoons - Witch Doctor":1998,"The Prodigy - Voodoo People":1994,
 "Lady Gaga & Bruno Mars - Die With A Smile":2024,"SZA - Kill Bill":2022,"Dua Lipa - Levitating":2020,"Lizzo - About Damn Time":2022,"Justin Timberlake - Can't Stop The Feeling!":2016,"Sophie Ellis-Bextor - Murder On The Dancefloor":2001,
 "Robyn - Dancing On My Own":2010,"The Weeknd - Save Your Tears":2020,"Robyn - With Every Heartbeat":2007,"Lady Gaga & Ariana Grande - Rain On Me":2020,"Robyn - Call Your Girlfriend":2011,"Kylie Minogue - Padam Padam":2023,"Sam Smith & Kim Petras - Unholy":2022,
 "Zara Larsson - Midnight Sun":2025,"Ginuwine - Pony":1996,"Livin' Joy - Dreamer":1995,"Robyn - Show Me Love (1997)":1997,"Riton x Nightcrawlers - Friday (Dopamine Re-Edit)":2021,"Tiesto & Tate McRae - 10.35 (VIP Mix)":2022,"ATB, Topic & A7S - Your Love (9PM)":2021,
 "Lana Del Rey vs Cedric Gervais - Summertime Sadness (Remix)":2013,"Roger Sanchez - Another Chance":2001,"LF System - Afraid To Feel":2022,"Peggy Gou - (It Goes Like) Nanana":2023,"Dario G - Sunchyme":1997,"William Orbit - Barber's Adagio For Strings (Ferry Corsten Remix)":1999,
 "Eliza Rose - B.O.T.A. (Baddest Of Them All)":2022,"Kenya Grace - Strangers":2023,"Beyonce - Break My Soul (The Queens Remix)":2022,"Slayyyter - Brand New Chanel$":2023,"Dom Dolla & Tiga - Don't Worry Baby":2025,"Fcukers - If You Wanna Party, Come Over To My House":2024,
 "Royksopp & Robyn - Monument":2014,"Royksopp & Robyn - Do It Again":2014,"Panic! At The Disco - I Write Sins Not Tragedies":2006,"Pretty Ricky - Grind With Me":2005,"My Chemical Romance - Teenagers":2006,"The Darkness - I Believe In A Thing Called Love":2003,"Coldplay - Viva La Vida":2008,"LCD Soundsystem - Daft Punk Is Playing At My House":2005,
}
REC_DISC = {  # on-disc tracks to recommend; originals that now have a dance version are left out on purpose
 # CD1 (to 1999)
 "Ginuwine - Pony","Coolio - Gangsta's Paradise","The Cranberries - Zombie","Ricky Martin - Livin' La Vida Loca",
 "Britney Spears - ...Baby One More Time","TLC - No Scrubs","Mark Morrison - Return Of The Mack","The Notorious B.I.G. - Hypnotize","Ace Of Base - All That She Wants",
 "Backstreet Boys - Everybody (Backstreet's Back)","Will Smith - Gettin' Jiggy Wit It","Stevie Wonder - Superstition",
 "Spice Girls - Wannabe","Bell Biv DeVoe - Poison","C+C Music Factory - Gonna Make You Sweat","Madonna - Vogue","Ray Parker Jr. - Ghostbusters","Michael Jackson - Thriller",
 "Robin S - Show Me Love","CeCe Peniston - Finally","Snap! - Rhythm Is A Dancer","Haddaway - What Is Love","Technotronic - Pump Up The Jam","Rob Zombie - Dragula","Nightcrawlers - Push The Feeling On",
 "Gala - Freed From Desire","Everything But The Girl - Missing (Todd Terry Mix)","Moloko - Sing It Back","Dead Or Alive - You Spin Me Round","Corona - The Rhythm Of The Night","Duran Duran - Hungry Like The Wolf",
 "Aqua - Barbie Girl","Depeche Mode - Personal Jesus","The Prodigy - Breathe","Robert Miles - Children","2 Unlimited - No Limit",
 # CD2 (2000 to now)
 "Beyonce - Haunted","OutKast - Hey Ya!","50 Cent - In Da Club","Kanye West - Gold Digger","Snoop Dogg - Drop It Like It's Hot","Beyonce - Crazy In Love",
 "Shakira - Hips Don't Lie","Lady Gaga - Bloody Mary","Doja Cat - Paint The Town Red","Dua Lipa - Levitating","Usher - Yeah!","Nelly - Hot In Herre",
 "Christina Aguilera, Lil' Kim, Mya, P!nk - Lady Marmalade","Gnarls Barkley - Crazy","Britney Spears - Gimme More","Tame Impala & Jennie - Dracula (Jennie Remix)","Mark Ronson - Uptown Funk","Justin Timberlake - SexyBack","Sophie Ellis-Bextor - Murder On The Dancefloor","Robyn - Dancing On My Own","Lady Gaga - Just Dance","Lady Gaga - Bad Romance",
 "Lady Gaga - Monster","Kesha - TiK ToK","Lady Gaga - Zombieboy","Riton x Nightcrawlers - Friday (Dopamine Re-Edit)","Dua Lipa - Don't Start Now","Kylie Minogue - Can't Get You Out Of My Head","Beyonce - Break My Soul (The Queens Remix)","Flo Rida - Low","Black Eyed Peas - I Gotta Feeling","Kylie Minogue - Padam Padam",
 "Sam Smith & Kim Petras - Unholy","Yeah Yeah Yeahs - Heads Will Roll (A-Trak Remix)","Ava Max - Sweet But Psycho","Gorillaz - Feel Good Inc","Britney Spears - Toxic",
}
CUT = {"Will Smith - Gettin' Jiggy Wit It","Christina Aguilera, Lil' Kim, Mya, P!nk - Lady Marmalade","Britney Spears - Gimme More","Lady Gaga - Monster","Lady Gaga - Zombieboy",
       "Kylie Minogue - Can't Get You Out Of My Head","Kylie Minogue - Padam Padam","Sam Smith & Kim Petras - Unholy","Gorillaz - Feel Good Inc","Bell Biv DeVoe - Poison",
       "C+C Music Factory - Gonna Make You Sweat","CeCe Peniston - Finally","Technotronic - Pump Up The Jam","Depeche Mode - Personal Jesus","Ricky Martin - Livin' La Vida Loca",
       "Corona - The Rhythm Of The Night","Duran Duran - Hungry Like The Wolf"}
REC_DISC = REC_DISC - CUT
REPLACED = {  # on-disc original -> the dance version that takes its slot
 "Rihanna - Disturbia": "DJ Mag Halloween Remix", "Talking Heads - Psycho Killer": "Freejak Halloween Remix", "Rockwell - Somebody's Watching Me": "Tall Boys Halloween Remix",
 "Beatfreakz - Somebody's Watching Me (2006)": "Tall Boys Halloween Remix", "Sisqo - Thong Song": "Colin Jay Remix", "Estelle - American Boy": "Aurelios Remix", "Cher - Believe": "Disco Dom Remix",
 "Rick James - Super Freak": "Rob DVS Super Freaky Girls Halloween Edit", "Missy Elliott - Get Ur Freak On": "DJ Bizzon Halloween Theme transition", "Lady Gaga - Abracadabra": "DJ intro version", "Yeah Yeah Yeahs - Heads Will Roll": "A-Trak Remix (already on CD3)", "Kelis - Milkshake": "Milkshake 20 (Alex Wann Remix)",
 "Bobby Boris Pickett - Monster Mash": "Lincoln Baio Remix", "Little Nell - Time Warp": "1989 Damian remix",
 "Mark Morrison - Return Of The Mack": "Tall Boys intro edit at 103", "50 Cent - In Da Club": "Disco Lines remix (125)", "Bette Midler - I Put A Spell On You (Hocus Pocus)": "Thee Werqn' Btches club mix at 140", "Olivia Rodrigo - Vampire": "Trayze remix", "Nelly - Hot In Herre": "Colin Jay intro edit", "Snoop Dogg - Drop It Like It's Hot": "Golden Pony remix",
 "Ciara - Goodies": "Dillon Francis flip with the Tall Boys clap intro (126)", "Montell Jordan - This Is How We Do It": "Mahalo 90s Baby rework (123)", "Next - Too Close": "Tom Damage remix (124)",
 "Dua Lipa - Levitating": "Blessed Madonna remix", "Doja Cat - Paint The Town Red": "FRASER bootleg at 126", "Stevie Wonder - Superstition": "Spooki remix (Mix-ins disc)",
 "Ace Of Base - All That She Wants": "SNBRN & Klatch remix (Mix-ins disc)", "The Cranberries - Zombie": "Johan K & Rinat Bibikov dance cover (Mix-ins disc)", "Blackstreet - No Diggity": "Tall Boys edit at 105 and the Rogerson & Ray Montreal edit at 126", "Nelly Furtado - Promiscuous": "ON_1 & SHADDA remix", "Daft Punk - One More Time": "Tall Boys Club Edit",
}
NOTE_DISC = {
 "Rihanna - Umbrella": "Benched: 87 BPM is the hard case. The Seamus Haji club remix (list #2) is the fix; tick this only if you want the original anyway.",
 "Ginuwine - Pony": "True classic, stays as the original. Ask the pool for an intro edit if one exists.", "Backstreet Boys - Everybody (Backstreet's Back)": "The Halloween video; singalong and theme track in one.",
 "Robert Miles - Children": "Easy to layer; the 137 breather that does not kill the floor.", "Beyonce - Haunted": "Spooky downtempo tool for a lull.", "John Carpenter - Halloween Theme": "Benched: the Get Ur Freak On transition already carries this theme. Tick it if you want the standalone tool too.",
 "Lady Gaga - Bloody Mary": "The Wednesday dance.", "Robyn - Dancing On My Own": "The midnight scream-along.", "Nightcrawlers - Push The Feeling On": "From CD4: easy to layer, everyone knows it.",
 "Everything But The Girl - Missing (Todd Terry Mix)": "From CD4: long intro, layers under anything.", "Moloko - Sing It Back": "From CD4: a 90s house vocal the room sings.", "Riton x Nightcrawlers - Friday (Dopamine Re-Edit)": "From CD4: the easiest blend on the disc.",
 "Beyonce - Break My Soul (The Queens Remix)": "Your single; house tempo, big vocal.", "Stevie Wonder - Superstition": "Halloween staple at 100; a pool intro edit would help.",
}
NEW = {  # file fragment -> (recommend, original year, halloween, why)
 "Maneater - Rogerson": (1, 2006, 1, "Your list pick #1: theme-perfect, club tempo, mixable intro."), "Maneater - Monaark": (0, 2006, 0, "Second Maneater; the Rogerson cut covers it."),
 "Psycho Killer - Freejak": (1, 1977, 1, "List pick #5; the clean version, a 130 house flip of the original."), "Somebody's Watching Me - Tall Boys": (1, 1984, 1, "List pick #6; short and punchy, replaces the original."), "Somebody's Watching Me - Richastic": (0, 1984, 1, "Second cut of the same song; tempo tag doubtful."),
 "No Diggity - Rogerson": (1, 1996, 0, "Floor-tempo No Diggity at 126; replaces the original."), "No Diggity - Tall Boys": (1, 1996, 0, "No Diggity at 105 with the vocal: the mixable version for the hip-hop folder."),
 "One More Time - Tall Boys": (1, 2000, 0, "List pick; club edit with an intro."), "Disturbia - DJ Mag": (1, 2008, 1, "Replaces the original; same tempo, DJ intro."),
 "Don't Stop The Music - Spryte": (1, 2007, 0, "The missing original, in a house edit."), "Don't Stop The Music - Colin Jay": (0, 2007, 0, "Second cut; Spryte's is the safer one."),
 "Rude Boy - Matthew Topper": (1, 2010, 0, "Rihanna at 130 with a hook mash."), "Pon De Replay - RUGGED": (1, 2005, 0, "Short, 120, an easy step up from the hip-hop folder."),
 "Believe - Disco Dom": (1, 1998, 0, "Club version of Believe; the original is benched."), "American Boy - Aurelios": (1, 2008, 0, "Replaces the original at house tempo."),
 "Modjo - Lady": (1, 2000, 0, "Filter-house classic in a fresh edit; the room knows the hook."), "Gypsy Woman": (1, 1991, 0, "ALRT edit of the 91 house classic; easy to layer."),
 "Stranger Things": (1, 2016, 1, "Halloween theme the room knows, at 128."), "Super Freak - Rob DVS": (1, 1981, 1, "Super Freak into Super Freaky Girl; replaces the original."),
 "NOKIA - MarkCutz": (1, 2025, 1, "Current, with a ringtone intro gag that lands on Halloween."), "WAP - Lincoln Baio": (1, 2020, 1, "Addams Family intro into WAP; explicit."),
 "Lose Control - Matthew Topper": (1, 2005, 0, "The missing Missy original, mashed over In This Bih' at 130."), "Lose Control (Extended": (0, 2005, 0, "137 kbps YouTube rip; the pool edit covers the song."),
 "In This Bih' - MarkCutz": (0, 2010, 0, "Same Chris Lorenzo beat as the Lose Control edit; one In This Bih' per night. Tick this one instead if you prefer The Time (Dirty Bit)."), "Promiscuous - ON_1": (1, 2006, 0, "Replaces the original at 130."),
 "Thong Song - Colin Jay": (1, 1999, 0, "Replaces the original; explicit."), "Abracadabra (Intro)": (1, 2025, 1, "DJ intro version replaces the album cut."), "Runway (Intro": (0, 2025, 0, "New Gaga and Doechii; 120 with an intro."),
 "OMG!": (0, 2025, 0, "Current club record; explicit."), "Cheetah Print": (0, 2025, 0, "Current; explicit."), "No Broke Boys (Intro": (1, 2025, 0, "The intro version is the one to keep."), "No Broke Boys (Acap": (0, 2025, 0, "Acapella-in version; keep the Intro cut."), "No Broke Boys (Dirty)": (0, 2025, 0, "Plain version; keep the Intro cut."),
 "Von Dutch": (1, 2024, 0, "Brat summer at 130; explicit."), "Bad Bunny - DtMF": (1, 2025, 0, "DtMF over Better Off Alone; a 90s bridge inside a current hit."), "Put Your Hands Up For Detroit": (0, 2006, 0, "Mike's lane; CD4 already covers this. Tick if you want it here too."),
 "Let Me Think About It": (0, 2007, 0, "Mike's lane, 5:32; CD4 territory. Tick if you want it here."), "Empire State Of Mind - Krooner": (1, 2009, 0, "A singalong moved to 120 house: exactly the kind of replacement you asked for."), "Bulletproof": (1, 2009, 0, "N9 edit; 128, instantly known."),
 "We Are Family": (1, 1979, 0, "Disco-house edit; a classic made mixable."), "Lost_In_Music": (0, 1979, 0, "Dimitri From Paris, 7:51: Mike's long blend; tick it if you want it on the disc rather than CD4-style."), "Got Your Money": (1, 1999, 0, "ODB over Genie In A Bottle; fun 124 bridge."),
 "Nicole Kidman": (1, 2025, 0, "140, an energy spike; explicit."), "Pink Pony Club": (1, 2020, 0, "Party in the U.S.A. mash; the one E and Diana will want."), "Pink Pony Club - Lincoln Baio Party In the U.S.A. Remix (1)": (0, 2020, 0, "Duplicate file."),
 "Don't Tell 'Em": (0, 2014, 0, "105 R&B club cut with an intro; explicit."), "Fat Juicy & Wet": (0, 2025, 0, "Current; explicit."), "Just a Lil Bit": (0, 2005, 0, "100 BPM club edit; explicit."),
 "Rich Baby Daddy": (0, 2023, 0, "Tempo unclear (tag 70, reads 94); audition first."), "Low - URAI": (0, 2007, 0, "Two-minute double-time flip; the original Low is in."),
 "Get Ur Freak On - DJ Bizzon": (1, 2001, 1, "Halloween theme that lands on Get Ur Freak On; replaces the original."), "Paint_The_Town_Red_x_SM": (0, 2023, 0, "128 kbps rip, remixer unknown; the original stays."),
 "Kelis_-_Milkshake_20": (1, 2003, 0, "List pick: the official 2023 Alex Wann house remix; replaces the original."),
 "All_That_She_Wants_Snbrn": (1, 1992, 0, "SNBRN & Klatch house remix at 118; the Mix-ins version of the singalong, so the original is benched."),
 "Demons (audio) - Epiphany": (1, 2023, 1, "Epiphany hip-hop flip of Demons, 70 (reads 140); a Mix-in."),
 "Paint The Town Red (FRASER": (1, 2023, 1, "FRASER house bootleg at 126 with the vocal; replaces the original."),
 "Drop it like its hot (The Golden Pony": (1, 2004, 0, "Golden Pony remix at 122; replaces the original."),
 "Levitating - The Blessed Madonna": (1, 2020, 0, "List pick: the official club remix, 116; replaces the original."),
 "Zombie_Extended_Mix": (1, 1994, 1, "Johan K & Rinat Bibikov dance cover at 122 with a new vocal; a Mix-in, and the slow original is benched."),
 "Return Of The Mack - Lincoln Baio": (1, 1996, 0, "Little Bit Yours mash edit at 123; a Mix-in."),
 "Return Of The Mack - Tall Boys Remix (Intro) (1)": (0, 1996, 0, "Duplicate file."),
 "Return Of The Mack - Tall Boys Remix (Intro)": (1, 1996, 0, "Pool intro edit at 103, vocal intact; replaces the original."),
 "Hot In Herre - Colin Jay": (1, 2002, 0, "Colin Jay intro edit at 124; replaces the original."),
 "Sam Robs & Kelvin Wood - No Scrubs": (1, 1999, 0, "House cover at 124 with a new vocal; a Mix-in. The TLC original stays as the classic."),
 "Superstition - Spooki": (1, 1972, 1, "Spooki remix at 123; a Mix-in, and the original is benched."),
 "Hypnotize_Soundtrack_Version": (0, 1997, 0, "Not an edit: the film cut of the original at 94. The album original is already on the disc."),
 "Umbrella (Jody den Broeder Lush Club": (1, 2007, 0, "Official Lush Club Remix, 9:12 at 126; Mike's long blend, a Mix-in."),
 "Jungle - PROBLEMZ": (1, 2024, 0, "Jungle's 2024 groove at 110; a Mix-in bridge between hip-hop and house tempos."),
 "Running Up That Hill": (1, 1985, 1, "Landis remix at 125; the Stranger Things song with the vocal intact. Singalong."),
 "Joel-Dickinson-Thee-Greatest-Hits-Bette-Midler": (1, 1993, 1, "Thee Werqn' Btches club mix of the Hocus Pocus song, 6:33 at 140; replaces the 66 BPM original you had ticked."),
 "In Da Club - Disco Lines": (1, 2003, 0, "Disco Lines house remix at 125, clean; replaces the original In Da Club you had ticked."),
 "Rich Baby Daddy (Intro": (0, 2023, 0, "Pool intro edit, tagged 146 (73 half-time); the usable Rich Baby Daddy, replacing the Gilla edit. Not in your picks."),
 "vampire - Trayze": (1, 2023, 1, "Trayze remix, tagged 155; replaces the 192 kbps vampire rip you had ticked. Audition the tempo."),
 "Monster Mash - Lincoln Baio": (1, 1962, 1, "List pick: the Lincoln Baio remix of Monster Mash, finally mixable; replaces the original."),
 "Pony (Wick-it Remix)": (1, 1996, 0, "Your Pony remix at 144 (you confirmed the double-time reading). Replaces the original."),
 "Thriller - Freejak": (1, 1982, 1, "Jolyon Petch's house cover of Thriller in the Freejak remix, 128. The MJ original stays as the classic; this is the floor version."),
 "Goodies - Tall Boys Clap Intro": (1, 2004, 0, "Dillon Francis house flip of Goodies with a Tall Boys clap intro, 126; replaces the 102 BPM original you had ticked."),
 "This Is How We Do It - Mahalo": (1, 1995, 0, "Mahalo's 90s Baby rework at 123, vocal intact; replaces the original you had ticked."),
 "Too Close (Tom Damage Remix)": (1, 1998, 0, "Tom Damage house remix at 124; replaces the 100 BPM original you had ticked."),
 "KATSEYE - GNARLY": (1, 2025, 0, "Amanda Sze remix rework at 135, 1:44; a current Mix-in for the top folder."),
 "Afraid To Feel (Extended) - LF SYSTEM": (1, 2022, 0, "Longer version of the cut on the disc; replaces it."),
 "Barbie Girl (Extended Mix) - Aqua": (1, 1997, 0, "Longer version of the cut on the disc; replaces it."),
 "Baby One More Time (Extended)": (1, 1998, 0, "Longer version of the cut on the disc; replaces it."),
 "This Is What You Came For ft. Rihanna (Extended Mix)": (1, 2016, 0, "Longer version of the cut on the disc; replaces it."),
 "Von Dutch (Extended Version)": (1, 2024, 0, "Longer version of the cut on the disc; replaces it."),
 "Dillon Francis - Goodies (Extended Mix)": (1, 2004, 0, "Longer version of the cut on the disc; replaces it."),
 "Demons [Extended Version]": (1, 2023, 1, "Longer version of the cut on the disc; replaces it."),
 "Don't Worry Baby (Extended Mix)": (1, 2024, 0, "Longer version of the cut on the disc; replaces it."),
 "Call On Me (Extended Edit)": (1, 2004, 0, "Longer version of the cut on the disc; replaces it."),
 "Summertime Sadness (Cedric Gervais Remix) - Spinnin": (1, 2013, 0, "Longer version of the cut on the disc; replaces it."),
 "Montell Jordan   This Is How We Do It Mahalo": (1, 1995, 0, "Longer version of the cut on the disc; replaces it."),
 "Murder On The Dancefloor (Extended Album Version)": (1, 2001, 0, "Longer version of the cut on the disc; replaces it."),
 "Nanana [Extended Mix]": (1, 2023, 0, "Longer version of the cut on the disc; replaces it."),
 "We Found Love (Calvin Harris Extended Mix)": (1, 2011, 0, "Longer version of the cut on the disc; replaces it."),
 "[Dopamine Re-Edit] [Extended]": (1, 2021, 0, "Longer version of the cut on the disc; replaces it."),
 "No Scrubs (Extended Mix) - BassTime": (1, 1999, 0, "Longer version of the cut on the disc; replaces it."),
 "Electricity (Extended Version)": (1, 2018, 0, "Longer version of the cut on the disc; replaces it."),
 "It Feels So Good (Extended Mix 1998)": (1, 2000, 0, "Longer version of the cut on the disc; replaces it."),
 "Dracula (feat. JENNIE) (Extended Remix)": (1, 2025, 1, "Longer version of the cut on the disc; replaces it."),
 "Witch Doctor (Extended Mix) - Cartoons": (1, 1998, 1, "Longer version of the cut on the disc; replaces it."),
 "brand new chanel (Extended) - Slayyyter": (1, 2023, 0, "Longer version of the cut on the disc; replaces it."),
 "Get It On (Joe T Vannelli": (1, 1971, 0, "Mike's request (Oct 24): Joe T. Vannelli's Vocal Attack house mix of T. Rex's Get It On, for CD2."),
 "Disco Lines - Got To Do (Extended Mix)": (0, 2024, 0, "Chris's pick (Oct 24): Disco Lines disco-house extended mix, for the pre-mixed set."),
 "Oliver Heldens & Will Clarke - Lost In Music (Extended Mix)": (0, 2024, 0, "Chris's pick (Oct 24): Oliver Heldens & Will Clarke house extended mix, for the pre-mixed set."),
 "Time_Warp_Remix_1989": (1, 1975, 1, "List pick: the 1989 Damian remix, 121 BPM; replaces the 87 BPM original. 128 kbps rip, so it will sound a touch thin."),
}
LIST_ORIG = {  # shopping-list originals already in the folder: title fragment -> (rec, era, why)
 "Temperature": (0, "2000s", "Sean Paul at 125; tick it if you want a dancehall moment."), "Move Your Feet": (0, "2000s", "Junior Senior; 118, bright and easy to mix."),
 "It Feels So Good": (0, "2000s", "Sonique; 2000 trance-pop, Mike-friendly."), "Call On Me": (0, "2000s", "Eric Prydz; 126, the filter-house staple."), "Strong Enough": (0, "90s", "Cher; 120, if Believe is not enough Cher."), "She Wolf": (0, "2000s", "Shakira; Halloween-adjacent, 126."),
}
NEW_BPM_OVERRIDE = {"Demons (audio) - Epiphany": 70, "Pony (Wick-it Remix)": 144, "Joel-Dickinson": 140, "Thriller - Freejak": 128, "Time_Warp_Remix_1989": 121, "Cardi B - WAP": 133, "Flo Rida - Low - URAI": 147, "Get Ur Freak On - DJ Bizzon": 90, "Lose Control (Extended": 125, "Lost_In_Music": 124, "Paint_The_Town_Red_x_SM": 130, "Nicole Kidman": 140}
EXT_FILES = {"Afraid To Feel (Extended) - LF SYSTEM": ["LF System - Afraid To Feel", "Extended"], "Barbie Girl (Extended Mix) - Aqua": ["Aqua - Barbie Girl", "Extended Mix"], "Baby One More Time (Extended)": ["Britney Spears - ...Baby One More Time", "Extended (fan edit)"], "This Is What You Came For ft. Rihanna (Extended Mix)": ["Calvin Harris - This Is What You Came For", "Extended Mix"], "Von Dutch (Extended Version)": ["Charli XCX - Von Dutch", "Extended Version"], "Dillon Francis - Goodies (Extended Mix)": ["Ciara - Goodies", "Dillon Francis Extended Mix"], "Demons [Extended Version]": ["Doja Cat - Demons", "Extended Version"], "Don't Worry Baby (Extended Mix)": ["Dom Dolla & Tiga - Don't Worry Baby", "Extended Mix"], "Call On Me (Extended Edit)": ["Eric Prydz - Call on Me", "Extended Edit"], "Summertime Sadness (Cedric Gervais Remix) - Spinnin": ["Lana Del Rey vs Cedric Gervais - Summertime Sadness (Remix)", "Cedric Gervais Extended Remix"], "Montell Jordan   This Is How We Do It Mahalo": ["Montell Jordan - This Is How We Do It", "Mahalo's 90s Baby Rework (extended)"], "Murder On The Dancefloor (Extended Album Version)": ["Sophie Ellis-Bextor - Murder On The Dancefloor", "Extended Album Version"], "Nanana [Extended Mix]": ["Peggy Gou - (It Goes Like) Nanana", "Extended Mix"], "We Found Love (Calvin Harris Extended Mix)": ["Rihanna - We Found Love", "Calvin Harris Extended Mix"], "[Dopamine Re-Edit] [Extended]": ["Riton x Nightcrawlers - Friday (Dopamine Re-Edit)", "Extended"], "No Scrubs (Extended Mix) - BassTime": ["Sam Robs & Kelvin Wood - No Scrubs", "Extended Mix (house cover)"], "Electricity (Extended Version)": ["Silk City & Dua Lipa - Electricity", "Extended Version"], "It Feels So Good (Extended Mix 1998)": ["Sonique - It Feels So Good", "Extended Mix 1998"], "Dracula (feat. JENNIE) (Extended Remix)": ["Tame Impala & Jennie - Dracula (Jennie Remix)", "Extended Remix"], "Witch Doctor (Extended Mix) - Cartoons": ["Cartoons - Witch Doctor", "Extended Mix"], "brand new chanel (Extended) - Slayyyter": ["Slayyyter - Brand New Chanel$", "Extended"]}  # Oct 23: longer versions pulled from the links page
FOLDERS = [(0, 89, "1 - under 90"), (90, 99, "2 - 90-99"), (100, 109, "3 - 100-109"), (110, 119, "4 - 110-119"), (120, 124, "5 - 120-124"), (125, 129, "6 - 125-129"), (130, 134, "7 - 130-134"), (135, 999, "8 - 135 plus")]
def folder_of(bpm):
    if not bpm: return "?"
    return next(n for lo, hi, n in FOLDERS if lo <= bpm <= hi)
def disc_of_era(era): return "S"   # placeholder; the category pass below sets S or M
M_NAMES = {"Robert Miles - Children","The Prodigy - Breathe","The Prodigy - Voodoo People","DJ Dado - X-Files","The Grid - Swamp Thing","Sash! - Mysterious Times","N-Trance - Set You Free",
           "Bomfunk MC's - Freestyler","Beyonce - Haunted","John Carpenter - Halloween Theme","Kylie vs New Order - Blue Monday Mashup","Beatfreakz - Somebody's Watching Me (2006)"}
M_NEW = ("GNARLY", "Gypsy Woman","Modjo - Lady","Put Your Hands Up","Let Me Think About It","Lost_In_Music","We Are Family","Bulletproof","Milkshake_20","Got Your Money","Empire State",
         "Get Ur Freak On - DJ Bizzon","In This Bih' - MarkCutz","Stranger Things","Jolyon Petch","Pony (Wick-it","Demons (audio)","Sam Robs","Zombie_Extended","Snbrn","Superstition - Spooki",
         "Lush Club","Jungle - PROBLEMZ","Return Of The Mack - Lincoln Baio","No Diggity - Rogerson","Rich Baby Daddy","Low - URAI","Maneater - Monaark","Paint_The_Town_Red_x_SM")

rows = []; used_paths = set()
# ---- A. the four discs ----
for disc, entries in discs.items():
    cd = disc[:3]
    for e in entries:
        name = e["name"]; f = final.get(name, {}); bpm = {"Doja Cat - Demons": 140}.get(name, f.get("bpm"))
        try: srcp = os.path.relpath(finder.find(e["key"], e["match"]), ROOT)
        except Exception: srcp = None
        if srcp: used_paths.add(srcp)
        built = [p for p in lp if p.startswith(f"CDs v2/{disc}/") and "_stale" not in p and finder.safe(name)[:40].lower() in p.lower()]
        pr = lp.get(built[0]) if built else (lp.get(srcp) if srcp else None) or {}
        year = (lp.get(srcp) or {}).get("year") if srcp else ""
        era = era_of(YEAR.get(name)) or KEY_ERA.get(e["key"]) or era_of(year) or ""
        kind = {"D": "dance original", "P": "pop original", "R": "slow / R&B", "A": "ambient"}[e["cls"]]
        if re.search(r"remix|re-edit|mix\)|vip", name, re.I): kind = "official remix"
        rec = name in REC_DISC; why = NOTE_DISC.get(name, "")
        if name in REPLACED: why = f"Benched: replaced by the {REPLACED[name]}."; rec = False
        intro = rec and bpm and bpm < 110 and e["cls"] in ("P", "R") and name not in ("John Carpenter - Halloween Theme",)
        if intro and "intro" not in why.lower(): why = (why + " " if why else "") + "Slow original: ask the pool for an intro or club edit so Mike can bring it in."
        rows.append({"id": hid("disc|" + disc + "|" + name), "title": name, "ver": "", "bpm": bpm, "secs": pr.get("secs", 0), "len": mmss(pr.get("secs", 0)), "mb": pr.get("mb", 0), "kbps": pr.get("kbps", 0),
                     "era": era, "hal": cd == "CD3", "kind": kind, "src": cd, "srclabel": f"on {cd} now", "path": built[0] if built else srcp, "disc": disc_of_era(era), "folder": folder_of(bpm), "rec": rec, "why": why, "list": None, "low": pr.get("kbps", 320) < 250, "intro": bool(intro)})
# ---- B. the new downloads ----
newfiles = list(newp)
for fn in newfiles:
    if fn.endswith(".mp4") or fn in used_paths: continue   # the Oct 17 singles are already on the discs
    pr = lp.get(fn) or {}; used_paths.add(fn)
    tag = next((v for k, v in sorted(NEW.items(), key=lambda kv: -len(kv[0])) if k in fn), (0, 2024, 0, ""))
    bpm = next((v for k, v in NEW_BPM_OVERRIDE.items() if k in fn), None)
    if bpm is None:
        t = (newp.get(fn) or {}).get("tag_bpm")
        bpm = int(t) if t else (round(aub.get(fn) / 1.015) if aub.get(fn) else (newp.get(fn) or {}).get("aubio"))
    if "Milkshake_20" in fn:
        p = subprocess.run(["aubiotrack", "-i", os.path.join(ROOT, fn)], capture_output=True, text=True); b = [float(x) for x in p.stdout.split()]
        iv = [y - x for x, y in zip(b, b[1:]) if 0.25 < y - x < 1.5]; bpm = round(60 / statistics.median(iv) / 1.015) if iv else None
    stem = re.sub(r"\.mp3$", "", fn); groups = []
    while True:
        m = re.search(r"\s*\(([^()]*)\)\s*$", stem)
        if not m: break
        groups.insert(0, m.group(1)); stem = stem[:m.start()]
    parts = stem.split(" - ")
    if any(frag in fn for frag in EXT_FILES): title, ver = next(tv for frag, tv in EXT_FILES.items() if frag in fn)
    elif "Milkshake_20" in fn: title, ver = "Kelis - Milkshake 20", "Alex Wann Remix"
    elif "Paint_The_Town" in fn: title, ver = "Doja Cat - Paint The Town Red", "SM remix (SoundCloud rip)"
    elif "Lost_In_Music" in fn: title, ver = "Sister Sledge - Lost In Music", "Dimitri From Paris Remix"
    elif "Time_Warp_Remix_1989" in fn: title, ver = "Richard O'Brien - Time Warp", "1989 Damian Remix (extended)"
    elif "Pony (Wick-it" in fn: title, ver = "Ginuwine - Pony", "Wick-it Remix"
    elif "Jolyon Petch - Thriller" in fn: title, ver = "Jolyon Petch - Thriller", "Freejak Remix (house cover)"
    elif "All_That_She_Wants_Snbrn" in fn: title, ver = "Ace Of Base - All That She Wants", "SNBRN & Klatch Remix"
    elif "Zombie_Extended_Mix" in fn: title, ver = "Johan K & Rinat Bibikov - Zombie", "Extended Mix (dance cover)"
    elif "Hypnotize_Soundtrack" in fn: title, ver = "The Notorious B.I.G. - Hypnotize", "Soundtrack Version"
    elif "Umbrella (Jody den Broeder" in fn: title, ver = "Rihanna - Umbrella", "Jody den Broeder Lush Club Remix"
    elif "Drop it like its hot" in fn: title, ver = "Snoop Dogg - Drop It Like It's Hot", "The Golden Pony Remix"
    elif "Demons (audio)" in fn: title, ver = "Doja Cat - Demons", "Epiphany Hip-Hop flip"
    elif "Sam Robs" in fn: title, ver = "Sam Robs & Kelvin Wood - No Scrubs", "house cover"
    elif "Jungle - PROBLEMZ" in fn: title, ver = "Jungle - PROBLEMZ", ""
    elif "Goodies - Tall Boys Clap" in fn: title, ver = "Ciara - Goodies", "Dillon Francis flip (Tall Boys Clap Intro)"
    elif "Too Close (Tom Damage" in fn: title, ver = "Next - Too Close", "Tom Damage Remix"
    elif "KATSEYE - GNARLY" in fn: title, ver = "KATSEYE - GNARLY", "Amanda Sze Remix Rework"
    elif "Joel-Dickinson" in fn: title, ver = "Bette Midler - I Put A Spell On You", "Thee Werqn' Btches Club Mix (Joel Dickinson)"
    elif "Oliver Heldens & Will Clarke - Lost In Music (Extended Mix)" in fn: title, ver = "Oliver Heldens & Will Clarke - Lost In Music", "Extended Mix"
    elif "Disco Lines - Got To Do (Extended Mix)" in fn: title, ver = "Disco Lines - Got To Do", "Extended Mix"
    elif "Get It On (Joe T Vannelli" in fn: title, ver = "T. Rex - Get It On", "Joe T. Vannelli Vocal Attack Mix"
    else:
        title = " - ".join(parts[:2]); ver = (" - ".join(parts[2:]) + " " + " ".join(f"({g})" for g in groups)).strip()
        title = title.replace("_Boris_", "'Boris'")
    lst = next((it for it in items if fold(title.split(" - ")[-1])[:10] in fold(it["track"]) and set(re.findall(r"[a-z]{4,}", fold(ver))) & set(re.findall(r"[a-z]{4,}", fold(it["version"])))), None)
    rows.append({"id": hid("new|" + fn), "title": title, "ver": ver, "bpm": bpm, "secs": pr.get("secs", 0), "len": mmss(pr.get("secs", 0)), "mb": pr.get("mb", 0), "kbps": pr.get("kbps", 0),
                 "era": era_of(tag[1]), "hal": bool(tag[2]) or "halloween" in fn.lower(), "kind": "pool edit" if pr.get("kbps", 0) >= 300 and "mp3.pm" not in fn else ("official remix" if "Milkshake_20" in fn or "Lost_In" in fn else "rip"), "src": "new", "srclabel": "new download", "path": fn, "disc": disc_of_era(era_of(tag[1])), "folder": folder_of(bpm), "rec": bool(tag[0]), "why": tag[3] + (" Explicit." if "(Dirty)" in fn and "explicit" not in tag[3].lower() else ""), "list": lst["rank"] if lst else None, "low": pr.get("kbps", 320) < 250})
# ---- C. shopping-list originals already in the folder ----
LIB = [p for p in lp if not p.startswith("CDs v2/")]
for frag, (rec, era, why) in LIST_ORIG.items():
    cands = [p for p in LIB if frag.lower() in os.path.basename(p).lower() and p not in used_paths]
    cands.sort(key=lambda p: -lp[p]["kbps"])
    if not cands: continue
    p = cands[0]; pr = lp[p]; used_paths.add(p)
    rb = fold_bpm(raw.get(p)); lst = next((it for it in items if frag.lower() in it["track"].lower()), None)
    rows.append({"id": hid("list|" + p), "title": lst["track"].split(" (")[0] if lst else os.path.basename(p), "ver": "", "bpm": rb, "rawbpm": True, "secs": pr["secs"], "len": mmss(pr["secs"]), "mb": pr["mb"], "kbps": pr["kbps"],
                 "era": era, "hal": frag == "She Wolf", "kind": "pop original", "src": "list", "srclabel": "in your folder, not on a disc", "path": p, "disc": disc_of_era(era), "folder": folder_of(rb), "rec": bool(rec), "why": why, "list": lst["rank"] if lst else None, "low": pr["kbps"] < 250})
# ---- D. everything else ----
seen_titles = {fold(r["title"]) for r in rows}
for p in LIB:
    if p in used_paths or "_stale" in p or p.startswith("Remix") or not p.lower().endswith(".mp3"): continue
    pr = lp[p]; key = next((k for k, v in finder.F.items() if v != "." and p.startswith(v + "/")), "TOP")
    if key == "COLL" and "Dance Hits Collection 90th" in p: key = "SUB"
    base = re.sub(r"\.mp3$", "", os.path.basename(p)); base = re.sub(r"^\s*(CD\d[ /-]*)?\d{1,3}[.\s_-]+", "", base).replace("_", " ")
    base = re.sub(r"\s*\((mp3\.pm|Official[^)]*|Lyrics|Audio|Video)[^)]*\)", "", base, flags=re.I).strip()
    title = f"{pr['artist']} - {pr['title']}" if pr.get("artist") and pr.get("title") else base
    rb = fold_bpm(raw.get(p)); era = era_of(pr.get("year")) or KEY_ERA.get(key, "")
    rows.append({"id": hid("lib|" + p), "title": title, "ver": "", "bpm": rb, "rawbpm": True, "secs": pr["secs"], "len": mmss(pr["secs"]), "mb": pr["mb"], "kbps": pr["kbps"], "era": era, "hal": key in ("HAL","PCA","PCK","PCM"),
                 "kind": "library", "src": "lib", "srclabel": KEY_LABEL.get(key, "folder"), "path": p, "disc": disc_of_era(era), "folder": folder_of(rb), "rec": False, "why": "", "list": None, "low": pr["kbps"] < 250, "dup": fold(title) in seen_titles})
json.dump(rows, open("newfiles/pool.json", "w"), indent=0, ensure_ascii=False)
import collections
print(len(rows), "rows;", collections.Counter(r["src"] for r in rows))
missing = [n for n in REC_DISC if not any(r["title"] == n for r in rows)]; print("unmatched REC names:", missing)
miss2 = [n for n in REPLACED if not any(r["title"] == n for r in rows)]; print("unmatched REPLACED names:", miss2)
nopath = [r["title"] for r in rows if r["src"] != "lib" and not r["path"]]; print("no path:", nopath)
import collections
for d in ("S", "M"):
    sel = [r for r in rows if r["rec"] and r["disc"] == d]
    print(f"{d}: {len(sel)} recommended, {sum(r['mb'] for r in sel):.0f} MB; candidates {sum(1 for r in rows if r['disc']==d and r['src']!='lib')}")
    c = collections.Counter(r["folder"] for r in sel); print("   folders:", ", ".join(f"{k}: {v}" for k, v in sorted(c.items())))
    print("   intro edits wanted:", [r["title"] for r in sel if r.get("intro")])

# ---------- duplicates and mash-up overlaps ----------
ELEMENTS = {  # mash-up element -> file/title fragments that contain it
 "In This Bih' (Chris Lorenzo)": ["Lose Control - Matthew Topper", "In This Bih' - MarkCutz"],
 "Halloween Theme (Carpenter)": ["Get Ur Freak On - DJ Bizzon", "John Carpenter - Halloween Theme"],
 "The Time (Dirty Bit)": ["In This Bih' - MarkCutz"], "Better Off Alone": ["Bad Bunny - DtMF"], "Genie In A Bottle": ["Got Your Money"],
 "Party In The U.S.A.": ["Pink Pony Club - Lincoln Baio"], "Super Freaky Girl": ["Super Freak - Rob DVS"], "Addams Family theme": ["WAP - Lincoln Baio"],
 "Million Dollar Baby": ["Rich Baby Daddy"], "Won't Be Possible (Mura Masa)": ["Rude Boy - Matthew Topper"],
}
ALIAS = {"milkshake 20": "milkshake", "the time warp": "time warp", "everybody": "everybody (backstreet's back)", "somebody watching me": "somebody's watching me", "lady": "lady (hear me tonight)"}
def song_key(r):
    t = r["title"].split(" - ", 1)[1] if " - " in r["title"] else r["title"]
    t = re.sub(r"\s*\((19|20)\d{2}\)", "", t); t = re.sub(r"\s*\(.*?\)\s*$", "", t) if not t.lower().startswith("everybody") else t
    k = fold(t).strip().rstrip("!").strip(); k = ALIAS.get(k, k)
    if k == "show me love": k += " / " + fold(r["title"].split(" - ")[0].split()[0])   # Robin S and Robyn are different songs
    return k
for r in rows:
    if r["src"] == "CD4" or r["title"] in M_NAMES or (r["src"] == "new" and any(f in r["path"] for f in M_NEW)): r["disc"] = "M"
    elif r["src"] == "lib": r["disc"] = "M" if r["srclabel"] == "MoS Electronic 90s" else "S"
    else: r["disc"] = "S"
# ---------- remix-first, no exceptions: any usable dance version in hand benches the original ----------
UNUSABLE = ("Low - URAI", "Paint_The_Town_Red_x_SM", "Lose Control (Extended", "Maneater - Monaark", "Hypnotize_Soundtrack", "(1).mp3", "No Broke Boys (Acap", "No Broke Boys (Dirty)", "Richastic", "Rich Baby Daddy", "Don't Stop The Music - Colin Jay")
def _skey(r):
    t = r["title"].split(" - ", 1)[1] if " - " in r["title"] else r["title"]
    t = re.sub(r"\s*\((19|20)\d{2}\)", "", t); t = re.sub(r"\s*\(.*?\)\s*$", "", t) if not t.lower().startswith("everybody") else t
    k = fold(t).strip().rstrip("!").strip(); return {"milkshake 20": "milkshake", "the time warp": "time warp"}.get(k, k)
_groups = collections.defaultdict(list)
for r in rows:
    if r["src"] != "lib": _groups[_skey(r)].append(r)
benched_now = []
for k, g in _groups.items():
    originals = [r for r in g if r["src"] != "new" and not re.search(r"remix|re-edit|mix\)|vip", r["title"], re.I)]
    versions = [r for r in g if r["src"] == "new" and not any(u in (r.get("path") or "") for u in UNUSABLE)] + [r for r in g if r["src"] != "new" and re.search(r"remix|re-edit|mix\)|vip", r["title"], re.I)]
    if not originals or not versions: continue
    if not any(v["rec"] for v in versions):
        best = sorted(versions, key=lambda v: (0 if v["src"] == "new" else 1, -(v["kbps"] or 0)))[0]; best["rec"] = True
    for o in originals:
        if o["rec"]:
            o["rec"] = False; names = ", ".join((v["ver"] or v["title"]) for v in versions if v["rec"])
            o["why"] = f"Benched: the {names} is in. Tick this to keep the original as well."; benched_now.append((o["title"], names))
print("newly benched originals:", benched_now)
seen = set()
for r in rows:   # the same track built onto two discs (Backstreet's Back on CD1 and CD3): recommend it once
    if r["src"] in ("CD1","CD2","CD3","CD4") and r["title"] in seen and r["rec"]: r["rec"] = False; r["why"] = "Same track as the CD1 copy; tick one."
    if r["src"] in ("CD1","CD2","CD3","CD4"): seen.add(r["title"])
cands = [r for r in rows if r["src"] != "lib"]
groups = collections.defaultdict(list)
for r in cands: groups[song_key(r)].append(r)
for r in cands:
    r["grp"] = []
    g = groups[song_key(r)]
    if len(g) > 1: r["grp"].append("same song: " + g[0]["title"].split(" - ", 1)[-1] + f" x{len(g)}")
    for el, frags in ELEMENTS.items():
        hits = [x for x in cands if any(f in (x.get("path") or "") or f in x["title"] for f in frags)]
        if any(f in (r.get("path") or "") or f in r["title"] for f in frags) and len(hits) > 1: r["grp"].append("shares " + el + f" x{len(hits)}")
for r in rows:
    if r["src"] == "lib": r["grp"] = []
USE_V2 = True  # Oct 23: Mike's returned list (selection_v2.json) is the baseline; swaps/ADDS/MOVES are already baked into it
SEL = json.load(open("newfiles/selection_v2.json" if USE_V2 else "newfiles/selection_v1.json")); sel_ids = {x["id"]: x["disc"] for x in SEL}
byid = {r["id"]: r for r in rows}
def _find(frag_title, frag_path=None):
    return next((r for r in rows if r["src"] != "lib" and frag_title in r["title"] and (frag_path is None or frag_path in (r.get("path") or ""))), None)
swaps = [  # (row to tick instead, row to untick)
    (_find("50 Cent - In Da Club", "Disco Lines"), _find("50 Cent - In Da Club", "/0")),
    (_find("Olivia Rodrigo - vampire", "Trayze"), None),
    (_find("Doja Cat - Demons", "CDs v2"), _find("Doja Cat - Demons", "Epiphany")),
    (_find("Bette Midler - I Put A Spell On You", "Joel-Dickinson"), _find("Bette Midler - I Put A Spell On You", "CDs v2")),
    (_find("Ciara - Goodies", "Tall Boys Clap"), _find("Ciara - Goodies", "CDs v2")),
    (_find("Montell Jordan - This Is How We Do It", "Mahalo"), _find("Montell Jordan - This Is How We Do It", "CDs v2")),
    (_find("Next - Too Close", "Tom Damage"), _find("Next - Too Close", "CDs v2")),
]
ADDS = {("50 Cent - Just a Lil Bit", "Bizzon"): ("M", "Added at your request; CD1 is full, so it sits in the CD2 100s folder."),
        ("KATSEYE - GNARLY", None): ("M", "Added at your request to the Mix-ins disc.")}
MOVES = ("ADÉLA - Nicole Kidman", "Drake & Sexyy Red - Cheetah Print", "Tiësto & Sexyy Red - OMG!", "Charli XCX - Von Dutch", "Bad Bunny - DtMF", "Disco Lines & Tinashe - No Broke Boys",
         "Jeremih - Don't Tell 'Em", "Rihanna - Rude Boy", "Missy Elliott - Lose Control", "Junior Senior - Move Your Feet", "Zara Larsson - Midnight Sun", "Slayyyter - Brand New Chanel$",
         "Sam Smith & Kim Petras - Unholy", "Icona Pop - I Love It")
for r in rows:
    if r["src"] == "lib": continue
    r["rec"] = r["id"] in sel_ids
    if r["id"] in sel_ids: r["disc"] = sel_ids[r["id"]]
    r["swapin"] = False
for tick, untick in ([] if USE_V2 else swaps):
    if tick: tick["rec"] = True; tick["swapin"] = True; tick["disc"] = "S"
    if untick:
        untick["rec"] = False
        if not untick["why"].startswith("Benched:"): untick["why"] = ("Benched: replaced by the " + (tick["ver"] or "new version") + ". " + untick["why"]).strip()
for (ft, fp), (disc, note) in ([] if USE_V2 else ADDS.items()):
    r = _find(ft, fp); assert r, ft
    r["rec"] = True; r["swapin"] = True; r["disc"] = disc; r["why"] = (r["why"] + " " + note).strip()
for r in rows:
    r["moved"] = False
    if not USE_V2 and r["src"] != "lib" and any(r["title"].startswith(m) for m in MOVES) and r["rec"]:
        r["disc"] = "M"; r["moved"] = True; r["why"] = (r["why"] + " " if r["why"] else "") + "Moved to Mix-ins to make CD1 fit; one click brings it back."
CUTS = {  # low-tempo trims (Oct 21): title -> reason; they stay on Mike's page as alternates
 "Coolio - Gangsta's Paradise": "80 BPM and dark; the slowest thing on the disc and nothing mixes into it.",
 "M.I.A. - Paper Planes": "86 BPM, one known chorus; sits between the hip-hop and pop tempos.",
 "Kanye West - Gold Digger": "The 90s-BPM hip-hop pocket is already covered by Hypnotize, the In Da Club remix and the Return Of The Mack edit.",
 "Shakira - Hips Don't Lie": "100 BPM reggaeton-pop that is awkward to blend; Crazy In Love and Yeah! carry that era better.",
 "Christina Aguilera, Lil' Kim, Mya, P!nk - Lady Marmalade": "4:25 vocal showcase with a slow build; hard to mix out of.",
 "Gnarls Barkley - Crazy": "Mid-tempo shuffle at 112; more of a listen than a dance.",
 "Lady Gaga - Monster": "Six Gaga tracks on one disc; Bad Romance, Bloody Mary, Just Dance and the Abracadabra intro cover her, and Monster is the least known.",
 "Scatman John - Scatman": "Novelty at 136, between the house folder and the 140s; still on old CD1.",
 "Beyonce - Crazy In Love": "99 BPM; Chris's call to trim the sub-100 pop end of CD1.",
 "Duran Duran - Hungry Like The Wolf": "Halloween by title only; the 80s slot is held by Somebody's Watching Me, Super Freak and Ghostbusters.",
 "Cartoons - Witch Doctor": "Novelty that gets one play at most, at an awkward 136.",
 "Lady Gaga - Zombieboy": "A 2024 deep cut most of the room will not know.",
 "Beyonce - Haunted": "67 BPM downtempo tool, 5:21; Mike still has it on old CD3 if he wants a lull.",
 "Major Lazer - Lean On": "98 BPM moombahton between tempos; on old CD2 already.",
 "Jeremih - Don't Tell 'Em": "105 BPM R&B cut; the lowest-tempo mix-in left after the trims.",
 "Jungle - PROBLEMZ": "110 BPM groove that bridges nothing once the slower tracks are gone.",
 "Daft Punk - Get Lucky": "6:10 full version at 116; a great singalong but long and mid-tempo, and on old CD4.",
}
APPLY_CUTS = False  # Oct 23 pm: the pasted list is authoritative, no extra benching
AGREED = {"Coolio - Gangsta's Paradise", "M.I.A. - Paper Planes", "Shakira - Hips Don't Lie",
          "Lady Gaga - Monster", "Scatman John - Scatman", "Beyonce - Crazy In Love", "Gnarls Barkley - Crazy"}
for r in rows:
    r["cut"] = False
    if APPLY_CUTS and r["src"] != "lib" and r["rec"] and r["title"] in CUTS and r["title"] in AGREED:
        r["rec"] = False; r["cut"] = True; r["why"] = "Benched: " + CUTS[r["title"]]
BASE141 = set(json.load(open("newfiles/baseline_141.json"))); BASE_DISC = json.load(open("newfiles/baseline_141_disc.json"))
for r in rows:
    if r["src"] != "lib" and not r["rec"] and r["id"] in BASE141 and not r["cut"]:
        r["cut"] = True
        if not r["why"].startswith("Benched:"): r["why"] = ("Benched: Mike took it off his list (Oct 23). " + r["why"]).strip()
    if r["src"] != "lib" and not r["rec"] and r["id"] in BASE_DISC: r["disc"] = BASE_DISC[r["id"]]   # keep the disc it was on
print("cut:", sum(1 for r in rows if r["cut"]), "of", len(CUTS), "+ Mike's removals")
print("moved:", sum(1 for r in rows if r.get("moved")))
print("swaps:", [(t["title"] if t else None, u["title"] if u else None) for t, u in swaps])
# Oct 24: the measured START tempo from the mixer analysis (mixer/features, in the tag's octave) replaces the tag for
# bpm, folder and ordering, so the deck shows the tempo the song actually starts at. Kept the tag when the tracker and
# the tag disagree by a non-octave ratio (3/2 etc.), since one of them is wrong and the tag has been right so far.
START_BPM_KEEP_TAG = {"Bette Midler - I Put A Spell On You"}   # Oct 24: 128 intro/outro around a 140 body; Chris keeps it at 140
_changed = []
for r in rows:
    if r["src"] == "lib" or r["title"] in START_BPM_KEEP_TAG: continue
    _fp = os.path.join("mixer", "features", r["id"] + ".json")
    if not os.path.exists(_fp): continue
    _f = json.load(open(_fp)); _lt = _f.get("local_tempo") or {}
    if _f.get("multiplier_vs_tag") not in ("1", "2", "1/2"): continue
    _b = float(_lt.get("bpm_in") or _f["bpm"]); _tag = float(r["bpm"] or _b)
    while _b > _tag * 1.5: _b /= 2
    while _b < _tag / 1.5: _b *= 2
    r["bpm_tag"], r["bpm_meas"], r["bpm"] = r["bpm"], round(_b, 1), int(round(_b))
    _nf = folder_of(r["bpm"])
    if _nf != r["folder"]: _changed.append((r["title"], r["bpm_tag"], r["bpm"], r["folder"], _nf, r["rec"]))
    r["folder"] = _nf
print(f"start-tempo override: {len(_changed)} tracks changed folder" + (": " + "; ".join(f"{t} {a}->{b} ({'on disc' if rec else 'alt'})" for t, a, b, fo, fn, rec in _changed if rec) if _changed else ""))
json.dump(rows, open("newfiles/pool.json", "w"), indent=0, ensure_ascii=False)
print("\nDuplicate groups among candidates:")
for k, g in sorted(groups.items()):
    if len(g) > 1: print(f"  {k} x{len(g)}: " + " | ".join((("REC " if x["rec"] else "    ") + (x["ver"] or "original") + f" [{x['srclabel']}]") for x in g))
print("\nShared elements:")
for el, frags in ELEMENTS.items():
    hits = [x for x in cands if any(f in (x.get("path") or "") or f in x["title"] for f in frags)]
    if len(hits) > 1: print(f"  {el}: " + " | ".join((("REC " if x["rec"] else "    ") + x["title"] + " · " + x["ver"]) for x in hits))
