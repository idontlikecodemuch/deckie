# Research X4: a key reader of Deckie's own without anyone labelling anything

Dated Nov 14, 2026. An answer to the owner's point after letter X3: hand labelling is off the table ("There has to be
a publicly labeled song option here."). Five parts: every public source of key labels not weighed before; routes
that need few or no labels, tried; the minor lean, fixed before the test score; the question for the attorney,
written to be sent as it stands; and the routes ranked. Builds on letters X2 (the trial) and X3 (training data that
could ship), and on D15, D16, D33 and D36. Scripts in `mixer/keytrial/` (`kt_x4.py`; commands in its README);
tables in `mixer/keytrial/x4_results.md`. **No audio, data set or weights are committed. Everything trained here is
for evaluation only.**
Tags: [opened] = the page or file was fetched and read on Nov 14, 2026; [snippet] = seen only as a search summary;
[inf] = my inference; [unmeasured] = not measured. Not legal advice.

## In plain words

A **label** is a song's key written down by a person. A **pseudo-label** is a key written down by a program
instead: here, by Deckie's untrained reader, and only when it is confident. **Self-supervised** training uses no
labels at all: the model is shown two snippets of one recording, one of them shifted in pitch by a known number of
notes, and learns that their keys must differ by exactly that shift. **Openly licensed audio** means recordings
whose own licence is CC BY, CC0 or public domain, the three that letter X3 found allow a shipped model. The **lean**
is how far a reader should favour minor when it is unsure; dance music is mostly minor, and the public labelled
songs are half major. The **bar** is D16's: exact key within five points of Apple's framework on the major half and
on the minor half of the 1,270 GiantSteps MTG clips (36.5 and 70.6).

SUMMARY_HERE

## 1. Public key labels not weighed before

Letter X3 covered the Freesound Loop Dataset, FMAK, the GiantSteps sets, and the classical and made-up sets. This
pass opened every other source I could find. "Human" means a person wrote the key; "machine" means a program did.
A source helps only if a human key and audio that may back a shipped model exist **for the same recording**.

| Source | Key labels: how many, who made them | Labels' terms (quoted) | Audio that could pair with them | Kind of music | Usable? |
|---|---|---|---|---|---|
| **MusicBrainz**, key as an attribute of a work [opened: statistics page] | 26,116 works (0.9 percent of 2.9 million); human editors; a key of the composition, not of a recording | "The core data of the database is licensed under the CC0"; whether this attribute's table is in the core set I could not confirm | none; MusicBrainz holds no audio, and no count of links to open audio is published | compositions; classical by every sign [inf] | No: no audio, wrong music |
| **Wikidata**, property P826 "tonality" [opened; counted by live query] | 7,896 items; human editors | "available under the Creative Commons CC0" | 632 items have a Wikimedia Commons audio file (Commons was weighed in X3) | 7,187 are compositions, 253 national anthems, 109 songs | No: classical, and tiny |
| **AcousticBrainz** [opened] | 29,460,584 submissions with "tonal information (including keys and scales)"; machine (the Essentia program run on users' own files) | "All of the data contained in AcousticBrainz is licensed under the CC0 license" | none: only features were ever uploaded | mixed, unstated | No: machine labels, no audio. Training on them would copy Essentia's reader, which the trial already beats |
| **Hooktheory** (TheoryTab) and the sets drawn from it [opened] | about 50 hours of songs; community | site terms forbid to "text-and-data mine" it, "including using it to train, fine-tune, or evaluate models"; the SheetSage copy is CC BY-NC-SA 3.0; another is "only for academic purposes" | none ("no audio is included") | pop | No |
| **Ultimate Guitar** [opened] | community chords | "personal, non-commercial use only" | none | pop, rock | No |
| **Chordonomicon** [opened] | 679,807 chord progressions scraped from user sites; no key column | CC BY-NC 4.0 | none (streaming-service ids) | mixed | No |
| **ChoCo**, 18 chord collections in one format [opened] | 20,029 key annotations; human | CC BY 4.0, except three parts at CC BY-NC-SA 4.0 | none; the audio parts refer to commercial recordings | jazz, pop, rock, classical | No: no audio |
| **RWC** [opened: 2026 paper] | key labels exist; human | "under a Creative Commons license (CC BY-NC 4.0)" | bundled, same licence | pop, jazz, classical | No: non-commercial |
| **Weimar Jazz Database** [opened] | 456 solos, key or tonal centre; human | Open Database License (share-alike) | none | jazz | No |
| **Rock Corpus** [opened] | 200 songs; human; home note only ("Major/minor distinctions are not recognized") | CC BY 4.0 | none (commercial recordings) | rock | No |
| **KeyFinder's test set** [opened: thesis] | 100 dance recordings "from the author's own DJ playlists", keys by two musicians | none stated | none | dance | No: no licence, no audio |
| **EDM-CUE** [opened] | 4,710 dance tracks; machine ("generated by rekordbox (possibly incorrect)") | MIT, metadata only | none (streaming-service ids) | all dance | No: machine labels, no audio |
| **Free Music Archive's Echo Nest table** [opened: the file itself] | 13,129 tracks; I read the column list: tempo, energy and six more, **no key or mode** | CC BY 4.0 | per track | mixed | No: no key in it |
| **Jamendo** and **MTG-Jamendo** [opened] | no key field | interface "freely for non-commercial uses"; the research set "solely for non-commercial research" | 55,000 tracks | mixed | No |
| **Freesound** beyond the Loop Dataset [opened] | a `tonality` field on every sound, machine ("estimated by a key detection algorithm"); uploaders' own keys only as free text in names and tags | each sound's licence "applies also to associated metadata"; the free interface is "only for non-commercial purposes" and says "Do not make full copies of the database" | per sound: CC0, CC BY or CC BY-NC; its own answer on training: "yes as long as individual sounds' Creative Commons licenses are respected" | loops and one-shots | Only through the Loop Dataset, already used. A bulk pull needs their commercial terms |
| **ccMixter** [opened: terms and a live query] | no key field; an occasional uploader tag ("key_of_csharp") | per upload, a Creative Commons licence | per upload | samples, remixes | Not counted; a small, uneven source at best |
| **Looperman**, **Splice**, **Loopmasters** [opened; the last a snippet] | keys in file names; vendor or uploader | "prohibited for anyone to use our content for the training or improvement of any algorithm"; Splice: may not "use the Sounds as source or training material for generative or other types of artificial intelligence models" | none | dance loops | No: training forbidden |
| **WaivOps** loop sets (hip-hop drums, lo-fi chords, house drums) [opened] | 8,000 chord loops rendered from note files by a program; whether the labels name a key is not confirmed | CC BY 4.0 | bundled, CC BY 4.0 | program-made | Made-up music, which X3 measured: no gain |
| **Slakh2100** [opened] | 2,100 pieces rendered from note files; no key label documented | CC BY 4.0 | bundled | program-rendered | Made-up music; no key |
| **MedleyDB**, **MUSDB18**, **MoisesDB**, **Cambridge-MT** (stems) [opened; the last a snippet] | no key labels | non-commercial or "academic purposes" | bundled | mixed | No |
| **Harmonix Set**, **CASD**, **USPop chords**, **JAAH**, **Robbie Williams set** [opened; the last a snippet] | chords or beats; keys in two of them | non-commercial, or none stated | none | pop, jazz | No |
| **Pixabay**, **YouTube Audio Library**, **Bandcamp**, **Incompetech**, **Open Music Archive** [opened] | no key anywhere | Pixabay forbids collection "for machine learning purposes"; YouTube forbids "automated means"; Bandcamp forbids commercial use | Incompetech is CC BY 4.0 | mixed | No key labels |
| Sets released since letter T (2024 to 2026) | searched; only FMAK and its revision (in X3) and a repackaging of FMAK ("tonic-trainer") | | | | Nothing new |

**What this says.** The owner is right that a public labelled option exists, and it is the one letter X3 already
used: 711 Freesound loops and 373 Free Music Archive songs, about 1,080 recordings. **Nothing larger exists.**
Every other body of human key labels either has no audio that may be used (chord and theory sites, MusicBrainz,
research sets on commercial recordings), forbids training outright (loop shops), or labels compositions that are
not dance music. The large "labelled" bodies (AcousticBrainz, EDM-CUE, Freesound's own field) are a program's
answers, not a person's. So more human labels are not coming from a public source, and the question becomes what
can be learned **without** them. That is section 2.

## 2. Routes that need few or no labels

### 2.1 How much openly licensed audio there is

Counted from each source's own licence field, not from a search page.

| Source | Recordings in all | CC BY, CC0 or public domain | of those, electronic or dance | Fetched here |
|---|---:|---:|---:|---|
| Free Music Archive (the research archive's track table, 106,574 tracks) [opened: the file] | 106,574 | **8,352** (CC BY 6,960; CC0 or public domain 1,392) | **2,745** electronic; 773 hip-hop | FETCHED_HERE |
| Freesound Loop Dataset [opened: the file, letter X3] | 9,455 | about 8,060 (711 with a human key, 7,346 without) | most | the 711 (letter X3) |
| Jamendo, ccMixter, Freesound at large | | not countable without their commercial terms or an account | | none |

Of the Free Music Archive, 78 percent is under non-commercial or no-derivatives licences and 3 percent under
share-alike; those are left out, as are the 428 tracks marked "Public Domain / Sound Recording Common Law
Protection", which is not a clean public-domain statement. **So the whole openly licensed pool within reach is
about 16,000 recordings, a third of them dance or electronic.** The published label-free readers trained on 60,000
to a million commercial songs (section 2.4); this pool is four to sixty times smaller.

EXPERIMENTS_HERE

## 4. For the attorney: the GiantSteps route

*Written to be sent as it stands. It states facts and asks questions; it does not answer them. Not legal advice.*

**What we want to do.** Ship, inside a paid app, a small program ("the model") that names the musical key of a
song on the user's own computer. The model is a list of 236,006 numbers (0.95 megabytes). Trained on the data
below, it meets our accuracy target; trained on any data whose licence plainly allows it, it does not.

**What was downloaded, from where, under what terms.** All of it on Nov 14, 2026, to a temporary disk of a cloud
session, for evaluation only. Nothing was put in our public repository; the disk is erased when the session ends.

| Set | From | What | Terms shown at the source |
|---|---|---|---|
| GiantSteps MTG Key ("Beatport EDM Key Dataset") | Zenodo record 1101082: `audio.zip` (2.13 GB) and `Beatport-EDM-Key-Dataset.xlsx` | 1,486 two-minute mp3 clips of commercial dance tracks, and a spreadsheet giving each clip's key as judged by the set's authors | The record's licence is CC BY-SA 4.0 (attribution, share-alike). The record says the clips "belong to online audio snippets from Beatport", an online music shop. No licence from the tracks' rights holders is shown |
| GiantSteps+ | Zenodo record 1095691: `audio.zip` (856 MB) and `GiantSteps+.xlsx` | 600 two-minute clips of the same kind, with revised keys | CC BY-SA 4.0 on the record; audio as above |
| GiantSteps Key | labels from `github.com/GiantSteps/giantsteps-key-dataset`; audio from `www.cp.jku.at/datasets/giantsteps/backup/` | 604 two-minute clips of the same kind, with keys | No licence statement found; audio as above |

We did not obtain the clips from Beatport, hold no account there for this purpose, and agreed to no terms of
Beatport's. The clips are the free previews Beatport's shop plays to any visitor; the research groups collected
them and republished them on the hosts above.

**What was done with it.** Each clip was decoded and turned into a picture of its pitch content over time (a
spectrogram: 126 pitch bands, five slices a second). The model was fitted so that its answer for each picture
matched the key in the spreadsheet. Only the first set (1,486 clips) would be trained on to ship; the other two are
used to test.

**What a trained model retains.** The 236,006 numbers are weights of small filters. They hold no audio, no
spectrogram and no list of the labels. We know of no way to recover any clip, or any recognisable part of one,
from them, and the model's only output is one of 24 key names with a confidence [inf: not tested by an attack]. The
model's behaviour is nonetheless shaped by both the recordings and the labels: trained without them, it is less
accurate.

**What would ship, and what would not.** The numbers would ship inside the app. No clip, spectrogram or label
would. The training copies would be deleted afterwards. We could publish the numbers themselves under CC BY-SA 4.0
with attribution to the set's authors, if that were required or helpful; the app's other code would stay
proprietary.

**The questions.**

1. **The recordings.** May we copy the 1,486 preview clips from the research archive, train the model on them,
   delete them, and sell an app that contains only the model, without a licence from the recordings' rights
   holders? Facts this turns on: where our company is established, where the training computer is, and where the
   app is sold (the rules for text-and-data mining and for fair use differ by country, and some allow rights
   holders to opt out); that the clips are two-minute excerpts made public as shop previews, obtained from a
   research republication and not from the shop; that the copies are temporary and the purpose is analysis (naming
   a key), not producing music; that the model cannot play back or generate audio; whether any rights holder or
   Beatport has published a reservation against such use; and whether Beatport's terms could bind us though we
   never accepted them.
2. **The labels.** The key labels are offered under CC BY-SA 4.0. Is a model fitted to them "adapted material"
   that must itself be offered under that licence, and if it must, does that duty stop at the model's numbers or
   reach the app that contains them? Facts this turns on: that each label is a short statement of fact about a
   recording (a key name) chosen by a person; that the model stores no label; whether a database right applies to
   the spreadsheet where we operate; that Creative Commons' own guidance treats training on share-alike material
   cautiously; and that we are able to publish the numbers under CC BY-SA 4.0 and keep the app's code separate.
3. **Exposure and remedy.** If the answer to 1 or 2 is uncertain rather than no, what is the realistic exposure of
   shipping, and would a commitment to withdraw the model on a rights holder's objection (our standing rule) and to
   fall back to a reader trained on nothing (which exists and ships today) limit it? Facts this turns on: that the
   model is replaceable in an app update with no loss of the user's data; that the app is sold directly and through
   app shops whose terms require us to hold the rights to what we ship; and that the same data has trained
   published research models for a decade, none of which we would be using.

RANKING_HERE

## What I could not verify

VERIFY_HERE
