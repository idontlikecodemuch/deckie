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

## Summary

- **The public labelled option exists and is already in use; nothing larger exists.** About 1,080 recordings have
  human key labels and licences that allow a shipped model (letter X3). Every other body of human key labels has no
  usable audio, forbids training, or is not dance music; the big "labelled" bodies are a program's answers
  (section 1).
- **Labels nobody typed are worth about as much as the human ones, and no more.** The untrained reader's confident
  answers on 8,332 openly licensed clips, used as labels, teach the 49-number reader to 58.9 exact on MTG (human
  labels: 58.8; the untrained reader itself: 57.8). Added to the human labels they change nothing measurable for
  the small model either (61.7 against 61.5). A model cannot learn from its teacher what the teacher gets wrong.
- **Learning with no labels at all did not work at this size.** Pretraining on pitch-shifted pairs of all 8,332
  clips barely learned (its answers lined up with human labels on 18 percent of held-out loops; chance is 8), and
  the model built on it is no better (59.0 exact on MTG). The published versions used 60,000 to a million songs.
- **A lean Deckie can justify exists, and it is too weak to matter.** Fixed before any score: the share of minor
  among the untrained reader's key answers on openly licensed electronic music. It came out at **55.2 percent**,
  barely off even. Applied once, it moves the minor half by under a point. **Nothing lawful reaches the bar as
  written**: the best misses the minor half by 8.6 points.
- **What does work: the small model trained only on lawful recordings is a better three-answer reader than the
  untrained one**, on every set: on MTG it shows a key on 73 percent of songs and is right on 70 percent of those
  (untrained: 70 and 65; Apple, showing every song: 65). That is letter `x4-key-complete.md`.
- **The GiantSteps route** stays the only one measured to pass the bar. The page for the attorney is section 4.
- **Ranking** (section 5): ship the lawful model behind the three answers now; ask the attorney about GiantSteps;
  do not spend more on label-free training or on the lean.


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
| Free Music Archive (the research archive's track table, 106,574 tracks) [opened: the file] | 106,574 | **8,352** (CC BY 6,960; CC0 or public domain 1,392) | **2,745** electronic; 773 hip-hop | all 8,352 thirty-second clips (7.9 GB), for evaluation only; 8,332 could be read |
| Freesound Loop Dataset [opened: the file, letter X3] | 9,455 | about 8,060 (711 with a human key, 7,346 without) | most | the 711 (letter X3) |
| Jamendo, ccMixter, Freesound at large | | not countable without their commercial terms or an account | | none |

Of the Free Music Archive, 78 percent is under non-commercial or no-derivatives licences and 3 percent under
share-alike; those are left out, as are the 428 tracks marked "Public Domain / Sound Recording Common Law
Protection", which is not a clean public-domain statement. **So the whole openly licensed pool within reach is
about 16,000 recordings, a third of them dance or electronic.** The published label-free readers trained on 60,000
to a million commercial songs (section 2.4); this pool is four to sixty times smaller.

### 2.2 Pseudo-labels: the untrained reader's confident answers as labels

The untrained three-answer reader was run over the 8,332 clips. Its answer is used as a label only when it is a key
(its two readings agree on the home note and the mode). No person is involved and the reader was fitted to nothing.

| | Clips | A key | Home note only | Not sure |
|---|---:|---:|---:|---:|
| All openly licensed clips | 8,332 | 5,252 (63.0 %) | 577 (6.9 %) | 2,503 (30.0 %) |
| Electronic | 2,730 | 1,726 | | |

**How right are these labels?** 372 of the clips are FMAK songs with an expert's key. Where the reader gave a key
(276 of them) it is the expert's key on **58.7 percent** (the home note on 60.9). On Beatport dance music its keys
are right on 65 to 85 percent; on this mixed music (rock, folk, experimental, thirty-second cuts) they are worse.
So four pseudo-labels in ten are wrong.

**What a model taught on them learns** (the 49-number learned profiles; exact key, percent):

| Taught on | MTG, 1,270: all | major | minor | GiantSteps+, 468 | GiantSteps Key, 604 |
|---|---:|---:|---:|---:|---:|
| Nothing (the untrained reader, every song given a key) | 57.8 | 54.4 | 59.3 | 76.9 | 60.9 |
| Pseudo-labels only, all genres (5,252) | 58.9 | 54.9 | 60.6 | 75.9 | 61.1 |
| Pseudo-labels only, electronic (1,726) | 59.4 | 53.9 | 61.8 | 77.1 | 61.4 |
| Human-labelled recordings (1,081; letter X3) | 58.8 | 56.0 | 60.1 | 78.0 | 62.6 |
| Human-labelled + pseudo-labels, all genres | 58.8 | 54.9 | 60.5 | 76.3 | 60.9 |
| Human-labelled + pseudo-labels, electronic | 58.9 | 53.6 | 61.2 | 77.8 | 62.1 |

And the small convolutional model (the pseudo-labelled clips capped at 2,000 for CPU time, drawn at random; read
at twelve pitch shifts as in letters X2 and X3):

| Taught on | MTG: all | major | minor | Bar as written | GiantSteps+ | GiantSteps Key |
|---|---:|---:|---:|---|---:|---:|
| Apple | 65.2 | 41.5 | 75.6 | | | |
| Human-labelled recordings (letter X3) | 61.5 | 63.5 | 60.6 | fails, minor 9.9 short | 80.1 | 63.1 |
| **Human-labelled + 2,000 pseudo-labels** | 61.7 | 62.7 | 61.2 | fails, minor 9.4 short | 78.4 | 62.9 |
| Pseudo-labels only (2,000) | still training when this was written (PSEUDO_ROW) | | | | | |

**What it says.**
- **Pseudo-labels alone match human labels for the small reader**: 58.9 against 58.8 on MTG, within a point or two
  on the others. That is a real finding: Deckie could have had its learned profiles with no human label at all.
- **They add nothing on top of human labels**, for either reader. The student cannot learn what the teacher gets
  wrong, and the teacher's errors here are the hard cases (mode, and the home note of sparse tracks).
- **What a student can learn beyond its teacher** is only what the audio shows consistently where the teacher was
  confident: here, a point of exact key from smoothing over the teacher's two readings. It cannot learn the mode
  better, because the labels it gets are the easy-mode songs only (the teacher declines the rest).

### 2.3 No labels at all: pitch-shifted pairs

After STONE (Kong and others, 2024), written here from the paper's idea, not its code. Two snippets of one clip are
in the same key; shift one by a known number of semitones and its key moves by that number. The model's 24 answers
are folded to 12 key signatures and placed on the circle of fifths; the loss asks each pair to differ by exactly
its shift, and each answer to be decided. Twelve passes over all 8,332 clips, then the model is taught on the
human-labelled recordings as in letter X3.

| | Result |
|---|---|
| First form of the loss (the batch's mean agreement) | did not move from its starting value in five passes: with every answer undecided at the start it has no slope. Stopped; the form above replaced it |
| Second form, twelve passes (20 minutes of CPU) | loss 1.15 to 1.00; the signatures line up with human labels on 17.6 percent of 188 held-out loops (chance: 8.3) |
| The model built on it, MTG exact: all / major / minor | 59.0 / 61.9 / 57.7 (from nothing: 61.5 / 63.5 / 60.6) |
| GiantSteps+ / GiantSteps Key | 81.4 / 63.7 (from nothing: 80.1 / 63.1) |

**It did not take.** The pretraining learned a little about key signatures and the model built on it is within
noise of, or below, the one trained from nothing. The published readers of this kind were trained on 60,000 songs
(STONE) and a million (S-KEY), for hundreds of passes on graphics processors; S-KEY then reaches 72 on the
GiantSteps Key set (weighted score) with no labels. Their weights cannot be used: STONE's carry no licence, S-KEY's
say "only for non-commercial research purposes", and both were trained on a streaming service's catalogue. **With
8,000 clips and one CPU this route is closed; with the whole 16,000-recording pool and a rented graphics processor
it is a research bet of a week or two, not a delivery.**

### 2.4 Coverage against precision, for every lawful reader

The readers as three-answer readers: confidence from the model's own probability, one number (a temperature)
fitted on human-labelled recordings the model did not learn from, a key shown at one half or more. Fixed before
scoring: the candidate of each kind is the one taught on the most lawful data; a learned reader "beats" the
untrained one if, showing keys on the same share of songs, its shown keys are right more often on MTG and on at
least one other set, and not worse by more than a point on the third. (Read at twelve pitch shifts here; the
reader as it ships, read once, is in `x4-key-complete.md`.)

| Reader (MTG, 1,270) | Key shown, percent of songs | Shown keys right | Shown keys right at the untrained reader's coverage (70.4) |
|---|---:|---:|---:|
| Untrained three-answer reader | 70.4 | 64.8 | 64.8 |
| Apple (every song given a key) | 100 | 65.2 | |
| Learned profiles, human + electronic pseudo-labels | 54.3 | 72.2 | 67.9 |
| **Small model, human + pseudo-labels** | 73.8 | 70.5 | **71.7** |
| Small model, pretrained with no labels | 67.6 | 70.5 | 70.1 |
| Small model, human-labelled only (letter X3; not calibrated) | 64.2 | 73.1 | 71.7 |

| At the untrained reader's coverage | GiantSteps+ (76.1 percent shown) | GiantSteps Key (73.8 percent shown) |
|---|---:|---:|
| Untrained three-answer reader | 85.4 | 69.1 |
| Learned profiles | 86.8 | 71.1 |
| **Small model, human + pseudo-labels** | **92.7** | **74.7** |
| Small model, pretrained with no labels | 91.6 | 74.0 |
| Small model, human-labelled only | 91.9 | 73.5 |

**Every learned reader beats the untrained one by the rule, and the small model by 5 to 7 points on every set.**
The gain comes from the human-labelled recordings: the model taught on them alone does as well. Pseudo-labels and
pretraining add nothing that can be measured.

## 3. The minor lean, treated honestly

**The rule, fixed in `kt_x4.py` before any test score was looked at:** the share of minor keys a trained reader
should lean to is the share of minor among the untrained reader's key answers on the openly licensed **electronic**
clips. It touches no test collection and no published count of another collection. It is applied in two ways, each
reported once: the training recordings weighed so that minor ones are that share of the fit (learned profiles),
and a finished model's minor answers raised as if its training mix had held that share (the small model).

One admission. The script was first run on the 1,725 clips that had been read by then, to check that it worked,
and it printed test scores with the lean those clips gave (61.9 percent, from 215 electronic clips). The rule was
not changed afterwards; the number below is the rule's on all 2,730 electronic clips.

| Top-level genre (Free Music Archive) | Clips | Given a key | Minor among those, percent |
|---|---:|---:|---:|
| **Electronic** | 2,730 | 1,726 | **55.2** |
| Hip-hop | 773 | 440 | 70.9 |
| Experimental | 2,496 | 1,380 | 55.6 |
| Rock | 1,771 | 1,122 | 54.5 |
| Pop | 1,368 | 962 | 35.1 |
| Folk | 1,190 | 789 | 36.2 |
| All | 8,332 | 5,252 | 51.4 |

**The lean is 55.2 percent minor.** Reported once:

| Reader, leaned to 55.2 percent minor (MTG, 1,270) | Exact: all | major | minor | Bar as written (36.5 / 70.6) |
|---|---:|---:|---:|---|
| Learned profiles, human-labelled | 58.9 | 56.5 | 60.0 | fails, minor 10.6 short |
| Learned profiles, human + electronic pseudo-labels | 58.9 | 53.6 | 61.2 | fails, minor 9.4 short |
| Small model, human-labelled (letter X3) | 61.3 | 62.2 | 61.0 | fails, minor 9.6 short |
| Small model, human + pseudo-labels | 61.9 | 61.7 | 62.0 | fails, minor 8.6 short |

**What it says.**
- **A justified lean exists and it is nearly no lean.** Openly licensed electronic music, as the untrained reader
  hears it, is 55 percent minor, not the 65 to 85 percent of Beatport's catalogue. Two reasons, neither separable
  here [inf]: the Free Music Archive's "Electronic" is wider than club music (ambient, chiptune, experimental), and
  the reader gives a key only where it is confident, which favours clear major songs.
- **The leans that nearly pass in letter X3 (65 and 85 percent) are published counts of Beatport's own catalogue**,
  the same shop the test clips come from. They are not counts of the test clips, so using them is not scoring on
  the test set; but they do tune the reader to that shop's mix. That is the honest description, and it is the
  owner's call whether it is within the rule that nothing is tuned to one body of music.
- **By the style a crate records: not possible today.** The crate's `style` block is a vector of numbers from the
  vocal tagger, with no named style, so there is nothing to look a published count up by. A lean by style would
  need a named-style reading first (a tagger whose classes include dance styles), and then a lawful count per
  style, which this pass did not find outside Beatport's.
- **So the bar as written cannot be reached honestly by leaning.** What separates the lawful model from Apple on
  the minor half is not the home note (75.4 against 76.4) but a habit: Apple answers minor when unsure, and the
  test collection is 70 percent minor. Section 5 says what to do about that.



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

## 5. The routes, ranked by likely delivery for least cost

| # | Route | What it delivers | Cost | Likelihood |
|---|---|---|---|---|
| 1 | **Ship the small model trained on lawful recordings, behind the three answers** | more keys shown and more of them right than the untrained reader on every set; on MTG the shown keys are right more often than Apple's are over all songs | done: `x4-key-complete.md`; one decision (publish its file) | certain, measured |
| 2 | **Ask the attorney about the GiantSteps route** (section 4) | the only route measured to pass the bar as written (65.9; 44.0 major, 75.5 minor) | one conversation; if yes, a day to retrain and swap the file | unknown; turns on the answers |
| 3 | Restate the bar for a reader that may decline | the bar was written for a reader that names a key for every song; a three-answer reader is judged on shown keys. On shown keys the lawful model already equals or beats Apple's overall rate | a decision, no work | the owner's call |
| 4 | More human-labelled dance music under open licences | each doubling of labelled data was worth 1 to 2 points in letter X2's curve | none exists to fetch (section 1); labelling is off the table | closed |
| 5 | Label-free pretraining at scale | perhaps the published 72 on GiantSteps Key, if 16,000 recordings are enough; they may not be | a rented graphics processor and one to two weeks | low |
| 6 | A stronger lean | nearly passes with Beatport's own share (letter X3) | none | not justified without a source outside Beatport (section 3) |
| 7 | More pseudo-labels | nothing: measured flat | none | closed |

**The one I would take: route 1 now, route 2 in parallel.** Route 1 is finished and gains 5 to 7 points of
precision at equal coverage for no legal question that was not already open in letter X3. Route 2 costs one
conversation and is the only way to the bar as written. I would not spend more on routes 5 to 7: each was tried
here and did not move the score.



## What I could not verify

- **MusicBrainz**: whether the key attribute's table is in the CC0 core set; what music the 26,116 keyed works
  are; any route from a keyed work to an openly licensed recording [could not open the search interface].
- **Could not open**: Chordify's terms, the RWC site, Cambridge-MT's terms, BandLab's, Loopmasters' licence,
  Uppbeat's, iReal Pro's. What is said of them above is from search summaries, or left out.
- **WaivOps and Slakh2100**: whether their labels name a key (the files were not fetched; both are program-made).
- **Freesound and ccMixter at large**: how many openly licensed loops state a key in their names or tags.
- **The open audio's own licences**: each Free Music Archive track's licence is the archive's 2017 record of it
  (`tracks.csv`), not checked track by track today.
- **Why the lean is 55 percent**: the two reasons in section 3 were not separated.
- **Label-free training at scale**: not tried beyond twelve passes on 8,332 clips on a CPU.
- **Calibration on other music**: the temperature was fitted on loops and songs that are not Beatport dance music;
  `x4-key-complete.md` reports how far the stated confidence is from the measured rate on each set.
- **The small model taught on pseudo-labels only** was still training when this was written; the learned profiles above are the evidence for that row.

