# Research P: how fast, and in how much memory, the crate builder runs on DJs' machines

Dated Oct 29, 2026. Question (Christopher): how would the engine behave on real machines rather than the cloud
machine it was measured on, and what speed and memory should a DJ expect on the Macs, Windows laptops, Linux
machines, iPads and iPhones musicians actually own? Read first: `core/README.md` ("Measuring memory"),
`docs/architecture/pc-linux-status.md` (entries 13 and 15), `a-on-device-analysis.md`, `l-non-apple.md`.

**Method and limits.** Nothing here was measured on the machines in the tables. One machine was measured: the cloud
machine the Windows and Linux track runs on (below). Every other row scales those measurements by published
processor figures; every such number is an estimate [inf], good to perhaps plus or minus 30 percent. Machine facts
come from a research pass with web search on Oct 28, 2026. Several vendor and survey pages refused the fetch
(Serato, Ableton, Native Instruments, Digital DJ Tips, the Geekbench browser), so some figures are from search
summaries, marked (2nd). This Mac (MacBook Pro, M1 Max, 10 cores, 32 GB) can be measured directly once ONNX Runtime's
macOS archive is fetched, which waits on Christopher's yes in the main session.

## Summary
1. **Memory does not depend on the machine.** One analysis of a four-minute track peaks at about 1.1 GB, 0.2 GB of it
   the two models shared by all jobs, and each further job at once adds about 0.9 GB (measured, after the memory work
   of Oct 28 and 29). Any computer running the same build allocates the same amounts.
2. **Speed depends mostly on the processor's vector arithmetic.** Three quarters of the time is the beat model, a
   neural network whose work is large multiplications of number grids. A 2024 to 2026 laptop should analyse a
   four-minute track in 4 to 6 s on its own and get through a 1,000-track library in about 1 to 1.5 hours; an M1 or
   M2 MacBook Air in about 2 hours; an older 8 GB Windows laptop in about 4 hours [inf].
3. **The cloud machine flatters some laptops and not others.** It is a server processor with AVX-512, arithmetic
   twice as wide as the AVX2 most Intel laptops have, so a general benchmark score would overrate those laptops for
   this work. The estimates scale the beat model by vector width times clock and the rest by single-core scores.
4. **Off the virtual machine** the memory is the same and the giving-back of memory between chunks costs less,
   because a virtual machine makes every first touch of fresh memory more expensive. Long batches on a fanless
   MacBook Air or a thin Windows laptop slow down as they heat; the tables allow 15 to 25 percent for it.
5. **The default job count is too generous on two kinds of machine.** `defaultJobs` (one job per core, 1 GB each,
   2 GB left over) puts 6 jobs and a 5.9 GB peak on an 8 GB MacBook Air, and 14 jobs and a 13.5 GB peak on a 16 GB
   Core Ultra laptop, mostly on efficiency cores that add little speed. A rule of one job per performance core with at
   least 3 GB or a quarter of memory left over halves the peak on those machines for 7 to 21 percent more time (table 2).
6. **iPad and iPhone do not run this engine.** Under D11 they use Apple's Music Understanding framework (11.8 s a track
   median in the simulator, stage 1). This engine's 1.1 GB would fit one job on 6 GB and larger devices; Apple's
   per-app memory ceiling sits near 6 GB on 8 and 12 GB devices with the increased-memory entitlement (2nd, forums).

## 1. What the one measured machine is
A cloud virtual machine (KVM) on an Intel Xeon of the Sapphire Rapids generation at 2.1 GHz: four real cores, no
hyperthreads, AVX-512, 15 GB of memory and no swap, shared with other sessions' builds. Measured there, release
build, four-minute 44.1 kHz stereo files:

| Measure | Value |
|---|---|
| One job, seconds per track (before the memory work; after it, 8.6 to 9.1) | 8.3 |
| One job, seconds per track with the model on 1, 2, 4 threads | 21.7, 13.5, 8.8 |
| Four jobs at once, seconds per track (wall clock) | 6.7 to 7.0 |
| Peak memory, one job / four jobs (after the memory work) | 1.1 GB / 3.8 to 4.4 GB |

Measured per stage (one job, quiet machine, two passes): the beat model 6.5 s of 8.9 to 9.0 s; everything else 2.3 s
(loudness 0.5, vocal tagger 0.7, the rest under 0.3 each). So per track the beat model costs about 19 to 20
core-seconds of this machine's core and everything else about 2.3, mostly single-threaded; the beat model speeds up
about 3.1 times on 4 threads; four jobs on four cores run at about 80 percent of perfect sharing. (The tables were
first computed with 19 and 2.5; with the measured split every row moves by 0.2 s or less.) The model below reproduces the measurements (8.6 s for one job, 6.7 s per
track for four).

The memory work of Oct 29 first cost one job about 20 percent in speed (giving the beat model's memory back after
every 30-second chunk); giving it back only after a track's first and last chunk, the default since, measured at
the old speed (8.6 to 9.1 s a file against 8.3 to 9.8, run alternately) with the same 1.09 GB peak. Four jobs at
once peaked at 4.4 to 4.5 GB in `deckie-build`, so the tables' 0.95 GB a job may be a little high for the first jobs
and low for many; the per-job figure is the least certain number here.

## 2. How the rows are scaled
- **Beat model, per core:** fp32 multiply-adds per clock times the clock a core holds under load, against the cloud
  core's 32 per clock at about 2 GHz. Apple's M-series performance cores and Qualcomm's Oryon do 16 per clock (four
  128-bit units); Intel's laptop performance cores 16 (two 256-bit units, AVX2); AMD's Zen 4 16 (AVX-512 run as
  256-bit halves); efficiency cores a quarter to a half of their performance cores.
- **Everything else, per core:** the Geekbench 6 single-core ratio, the cloud core taken as about 1,450 (one Xeon
  Platinum 8370C run reads 1,316; a Xeon Gold 6338N reads 1,484 to 1,635).
- **One job:** the model's threads spread over all cores, speeding up as the thread count to the power 0.82
  (measured on four).
- **Many jobs:** one thread each on every core, 80 percent sharing efficiency, times the heat allowance.
- **Memory:** 0.2 GB plus 0.95 GB a job.

Not counted: ONNX Runtime may use Apple's matrix units (SME, on M4 and later) or Intel's AMX for some operations,
which would make those machines faster than shown; and ONNX Runtime splits a run evenly across threads, so a slow
efficiency core can hold the others up when one job uses all cores.

## 3. Table 1: estimates with the default job count as it is now
Four-minute tracks. "Jobs" is `defaultJobs` on that machine; "peak" the builder's memory at that count.

| Machine | Jobs | Peak | One track alone | Per track, batch | 1,000 tracks |
|---|---|---|---|---|---|
| Cloud machine (measured) | 4 | 4.0 GB | 8.6 s | 6.7 s | 1.9 h |
| MacBook Air M1, 8 GB | 6 | 5.9 GB | 7.7 s | 7.6 s | 2.1 h |
| MacBook Air M2, 8 GB | 6 | 5.9 GB | 7.0 s | 7.0 s | 1.9 h |
| MacBook Air M3, 16 GB | 8 | 7.8 GB | 6.1 s | 5.7 s | 1.6 h |
| MacBook Pro M1 Max, 32 GB (this Mac) | 10 | 9.7 GB | 5.6 s | 3.7 s | 1.0 h |
| MacBook Air M4, 16 GB | 10 | 9.7 GB | 4.9 s | 4.4 s | 1.2 h |
| MacBook Pro M4 Pro 14-core, 24 GB | 14 | 13.5 GB | 3.3 s | 2.0 s | 0.6 h |
| MacBook Air M5, 16 GB | 10 | 9.7 GB | 4.5 s | 4.0 s | 1.1 h |
| Windows, Intel Core Ultra 7 155H, 16 GB | 14 | 13.5 GB | 4.5 s | 3.4 s | 0.9 h |
| Windows, AMD Ryzen 7 7840U, 16 GB | 8 | 7.8 GB | 4.9 s | 4.0 s | 1.1 h |
| Windows on Arm, Snapdragon X Plus, 16 GB | 10 | 9.7 GB | 4.9 s | 3.5 s | 1.0 h |
| Windows, older Intel Core i5-8250U, 8 GB | 4 | 4.0 GB | 13.1 s | 14.4 s | 4.0 h |
| Linux desktop, AMD Ryzen 7 7700, 32 GB | 8 | 7.8 GB | 4.0 s | 2.6 s | 0.7 h |

The Ryzen 7 7700 row's processor figures are mine, not from the research pass. Windows on Arm needs ONNX Runtime's
Windows arm64 build, which `fetch-onnxruntime.sh` does not pin yet; Serato does not support Windows on Arm (2nd).

## 4. Table 2: a stricter default job count
One job per performance core, with at least 3 GB or a quarter of memory left for the system and other programs.

| Machine | Jobs | Peak | Per track, batch | 1,000 tracks | Time against table 1 |
|---|---|---|---|---|---|
| Cloud machine | 4 | 4.0 GB | 6.7 s | 1.9 h | same |
| MacBook Air M1 or M2, 8 GB | 4 | 4.0 GB | 7.4 to 8.1 s | 2.1 to 2.2 h | +7% |
| MacBook Air M3, 16 GB | 4 | 4.0 GB | 6.5 s | 1.8 h | +13% |
| MacBook Pro M1 Max, 32 GB | 8 | 7.8 GB | 3.8 s | 1.1 h | +4% |
| MacBook Air M4 or M5, 16 GB | 4 | 4.0 GB | 4.9 to 5.3 s | 1.4 to 1.5 h | +21% |
| MacBook Pro M4 Pro, 24 GB | 10 | 9.7 GB | 2.1 s | 0.6 h | +6% |
| Windows, Core Ultra 7 155H, 16 GB | 6 | 5.9 GB | 4.1 s | 1.1 h | +21% |
| Windows, Ryzen 7840U / Snapdragon X Plus / i5-8250U | 8 / 10 / 4 | 7.8 / 9.7 / 4.0 GB | as table 1 | as table 1 | same |
| Linux desktop, Ryzen 7 7700 | 8 | 7.8 GB | 2.6 s | 0.7 h | same |

Why it matters: rekordbox 7 asks for 8 GB and 16 GB for stems; VirtualDJ and Ableton Live 12 ask for 8 GB (2nd for
Ableton). A DJ's 8 GB laptop with macOS or Windows and a browser open has roughly 4 to 5 GB to spare, so a 5.9 GB
peak means swapping (macOS compresses then swaps, Windows pages to disk; a Linux machine without swap ends the
process). Finding the performance cores is one call on macOS (`hw.perflevel0.physicalcpu`) and on Windows
(`GetLogicalProcessorInformationEx`, `EfficiencyClass`); on Linux, Intel's hybrid chips list them in
`/sys/devices/cpu_core/cpus`, and other chips have only one kind.

## 5. iPad and iPhone
- **Engine:** Apple's Music Understanding framework (D11), not this one. Stage 1 measured 11.8 s a track median in the
  iPad simulator on this Mac; a real iPad is unmeasured. Scaled by Geekbench 6 single-core against this Mac's M1 Max
  (2,393) [inf]: an M4 or M5 iPad Pro or Air at roughly the simulator's speed or better, an A16 iPad (2,567) or an
  A17 Pro iPad mini (2,895) about the same, if the framework leans on the processor rather than the neural engine,
  which is unknown. 1,000 tracks at 12 s is about 3.3 hours, on power, with thermal pauses (spec 01, bulk work).
- **Memory, should this engine or Beat This! ever run there:** device memory (teardowns and Xcode lists): iPhone 13
  4 GB; iPhone 14, 15 6 GB; 15 Pro, 16, 17 8 GB; 17 Pro and Air 12 GB; iPad 10th generation 4 GB, 11th 6 GB; iPad
  Air M1 to M3 8 GB, M4 12 GB; iPad mini A17 Pro 8 GB; iPad Pro M4 8 or 16 GB, M5 12 or 16 GB. Apple publishes no
  per-app limit. Developers report a ceiling of about 6 GB on 8 and 12 GB iPhones with the increased-memory
  entitlement (forum thread 834805, June 2026), and a drop to about 3 GB on 8 GB iPads under iPadOS 26.4 and 26.5 that
  Apple attributed to address-space exhaustion and expected fixed in 26.6 (thread 826325). One job of this engine
  (1.1 GB) would fit on 6 GB devices and up; 4 GB devices would be at risk. Beat This! small (2M parameters, 8 MB)
  would need far less, unmeasured.

## 6. Who owns what
- Operating system among DJs: about even between Windows and macOS (Digital DJ Tips 2024 census and its 2026 laptop
  guide, 2nd); a 2023 figure of 60/40 Windows could not be confirmed. A small producers' forum poll (KVR, 418 votes,
  Jan 2025) reads Windows 46, macOS 27, Linux 10 percent.
- DJ software (2026 census, over 22,000 entries, 2nd): rekordbox 34, Serato 27, VirtualDJ about 17 percent.
- Floor for a DJ computer, from the vendors: 8 GB and AVX2 (Intel 5th generation, AMD Ryzen 1000 or later) or Apple
  M1; 16 GB for stems (rekordbox 7, fetched Oct 2026). Apple's current MacBook Air starts at 16 GB.
- Not found: the laptop and desktop split, and which machines DJs name most.

## 7. To replace estimates with measurements
1. This Mac (M1 Max) with `deckie-memprobe` and `deckie-build --jobs 1` and at the default, once ONNX Runtime's macOS
   archive is approved: the first Apple Silicon row measured, and the check on the vector-width scaling.
2. One Windows laptop with a hybrid Intel processor, and one 8 GB machine of any kind, by a tester who has them.
3. A real iPad and iPhone with the Music Understanding benchmark (`tools/mubench`), plugged in, thermal state logged
   (stage 1's open item).

## Sources
rekordbox 7 requirements, https://rekordbox.com/en/download/ (ver. 7.2.19, Sep 24, 2026). VirtualDJ requirements,
https://www.virtualdj.com/wiki/Requisitos%20m%C3%ADnimos%20de%20sistema.html (undated). Ableton Live computer
specifications, https://help.ableton.com/hc/en-us/articles/209775305 (2nd). Serato system requirements,
https://support.serato.com/hc/en-us/articles/227883108 (2nd). djay Pro for Mac requirements,
https://help.algoriddim.com/user-manual/djay-pro-mac/getting-started/requirements. Digital DJ Tips, 2024 census
https://www.digitaldjtips.com/census-results-2024/ , 2026 census facts
https://www.digitaldjtips.com/5-facts-about-djs-2026-census/ , DJ laptop guide https://www.digitaldjtips.com/dj-laptop-2026/
(all 2nd). KVR poll, https://www.kvraudio.com/forum/viewtopic.php?p=9023552 . Apple specifications,
https://www.apple.com/macbook-air/specs/ , https://www.apple.com/macbook-pro/specs/ , https://www.apple.com/mac-mini/specs/ .
Geekbench 6 averages for Apple devices, EveryMac (Oct 24, 2026),
https://everymac.com/mac-benchmarks/all-apple-silicon-macbook-air-benchmarks.html and its MacBook Pro, Mac mini and
iPad pages; Windows and Xeon scores from Notebookcheck, NanoReview and https://browser.geekbench.com/v6/cpu/baseline/17840514
(2nd except the last). iPhone memory, https://iphonescompare.com/iphone-ram-comparison (Sep 14, 2026); iPad memory,
https://9to5mac.com/2024/05/06/ipad-ram-list/ and https://everymac.com/systems/apple/ipad/all-current-ipad-models.html
(Oct 17, 2026). Apple Developer Forums threads 826325 and 834805; the increased-memory-limit entitlement,
https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit .
Beat This!, https://github.com/CPJKU/beat_this and arXiv 2407.21658.
