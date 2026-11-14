THE LEAN 55.2 percent minor. Learned profiles: 1081 human-labelled + 1726 electronic pseudo-labels; temperature 1.069 (out-of-fold exact on the human-labelled recordings 64.6)
small model, human-labelled only (X3): temperature 1.000 (no validation answers kept; not calibrated)

**MTG, 1,270**

| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | bar as written | shown keys right at the untrained reader's coverage (70.4) | expected by its own confidence there |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|
| untrained three-answer reader (ships now) | 70.4 | 64.8 | 78.0 | 11.7 | 79.2 | 17.9 | 55.6 | 63.2 | 52.3 | | 64.8 | |
| Apple (every song given a key) | 100.0 | 65.2 | 76.4 | | | | 65.2 | 41.5 | 75.6 | | | |
| learned profiles (49 numbers) | 54.3 | 72.2 | 84.8 | 20.2 | 75.9 | 25.4 | 58.9 | 53.6 | 61.2 | fails (major +17.2, minor -9.4) | 67.9 | 61.9 |
| small model, human-labelled only (X3), leaned | 64.2 | 73.1 | 86.1 | 12.8 | 77.9 | 23.0 | 61.3 | 62.2 | 61.0 | fails (major +25.7, minor -9.6) | 71.7 | 71.2 |
| learned profiles (49 numbers), and the untrained reader names the same key | 47.8 | 75.5 | | | | | | | | | | |
| small model, human-labelled only (X3), leaned, and the untrained reader names the same key | 44.3 | 79.2 | | | | | | | | | | |

**GiantSteps+, 468**

| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | bar as written | shown keys right at the untrained reader's coverage (76.1) | expected by its own confidence there |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|
| untrained three-answer reader (ships now) | 76.1 | 85.4 | 87.6 | 4.7 | 81.8 | 19.2 | 75.9 | 69.0 | 76.8 | | 85.4 | |
| learned profiles (49 numbers) | 68.6 | 88.2 | 89.7 | 10.7 | 82.0 | 20.7 | 77.6 | 70.7 | 78.5 |  | 86.8 | 71.1 |
| small model, human-labelled only (X3), leaned | 82.5 | 89.4 | 92.5 | 3.4 | 81.2 | 14.1 | 80.1 | 67.2 | 82.0 |  | 91.9 | 81.9 |
| learned profiles (49 numbers), and the untrained reader names the same key | 62.6 | 91.1 | | | | | | | | | | |
| small model, human-labelled only (X3), leaned, and the untrained reader names the same key | 63.9 | 94.0 | | | | | | | | | | |

**GiantSteps Key, 604**

| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | bar as written | shown keys right at the untrained reader's coverage (73.8) | expected by its own confidence there |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|---:|
| untrained three-answer reader (ships now) | 73.8 | 69.1 | 74.7 | 5.5 | 60.6 | 20.7 | 59.9 | 43.0 | 63.0 | | 69.1 | |
| learned profiles (49 numbers) | 65.6 | 73.2 | 78.3 | 11.1 | 64.2 | 23.3 | 61.9 | 44.1 | 65.2 |  | 71.1 | 70.1 |
| small model, human-labelled only (X3), leaned | 76.8 | 72.8 | 79.3 | 5.3 | 46.9 | 17.9 | 63.6 | 41.9 | 67.5 |  | 73.5 | 80.0 |
| learned profiles (49 numbers), and the untrained reader names the same key | 58.9 | 75.6 | | | | | | | | | | |
| small model, human-labelled only (X3), leaned, and the untrained reader names the same key | 58.9 | 77.0 | | | | | | | | | | |
