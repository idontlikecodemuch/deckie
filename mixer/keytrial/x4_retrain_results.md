Retrained models read as shipped, against the shipped reader. club: training mix 57.7 percent minor, lean -0.103, temperature 1.446, stopped at pass 104, exact on the validation artists 67.6; clubonly: training mix 65.6 percent minor, lean -0.436, temperature 1.446, stopped at pass 76, exact on the validation artists 68.6.

**MTG, 1,270**

| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | shown keys right at the shipped reader's coverage (73.1) | expected by its own confidence: shown keys |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| the shipped reader | 73.1 | 69.9 | 83.9 | 9.8 | 68.8 | 17.1 | 60.9 | 59.8 | 61.4 | 69.9 | 76.2 |
| retrained: club | 74.7 | 69.7 | 82.6 | 10.6 | 73.9 | 14.7 | 61.4 | 59.6 | 62.2 | 70.8 | 75.4 |
| retrained: clubonly | 73.4 | 66.2 | 82.7 | 9.9 | 65.9 | 16.7 | 58.8 | 62.4 | 57.2 | 66.4 | 74.5 |

**GiantSteps+, 468**

| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | shown keys right at the shipped reader's coverage (83.8) | expected by its own confidence: shown keys |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| the shipped reader | 83.8 | 89.3 | 91.3 | 3.2 | 73.3 | 13.0 | 79.9 | 69.0 | 81.5 | 89.3 | 82.1 |
| retrained: club | 82.7 | 89.1 | 90.7 | 5.1 | 70.8 | 12.2 | 80.6 | 70.7 | 82.0 | 88.5 | 81.8 |
| retrained: clubonly | 82.1 | 86.7 | 88.5 | 4.5 | 71.4 | 13.5 | 77.6 | 72.4 | 78.3 | 85.7 | 80.9 |

**GiantSteps Key, 604**

| reader | key shown, percent of songs | shown keys right | shown keys' home note right | home note only, percent | those home notes right | not sure | every song given a key: exact | major | minor | shown keys right at the shipped reader's coverage (80.0) | expected by its own confidence: shown keys |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| the shipped reader | 80.0 | 73.1 | 77.8 | 5.1 | 61.3 | 14.9 | 63.6 | 41.9 | 67.5 | 73.1 | 81.5 |
| retrained: club | 81.0 | 71.4 | 76.1 | 5.3 | 62.5 | 13.7 | 63.9 | 45.2 | 67.3 | 71.6 | 80.4 |
| retrained: clubonly | 79.0 | 69.4 | 74.6 | 5.5 | 60.6 | 15.6 | 62.6 | 48.4 | 65.2 | 68.7 | 79.9 |

club: at the shipped reader's coverage, shown keys right +0.9 on MTG, -0.8 on GiantSteps+, -1.4 on GiantSteps Key: does not replace the shipped reader by the rule.
clubonly: at the shipped reader's coverage, shown keys right -3.6 on MTG, -3.6 on GiantSteps+, -4.3 on GiantSteps Key: does not replace the shipped reader by the rule.
