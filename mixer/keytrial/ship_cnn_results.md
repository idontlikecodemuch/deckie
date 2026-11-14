minor share of the model's real training clips: 54.3 percent

| reader | trained on | set | exact: all | major | minor | mean of halves | within one step | home note | mode given home: major | minor | bar as written |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Apple | | MTG, 1,270 | 65.2 | 41.5 | 75.6 | 58.5 | 78.3 | 76.4 | 58.6 | 95.8 | |
| small convolutional model | real (loops, FMAK songs, Clavier) + 0 % made-up (stopped at pass 60, real validation 67.6) | MTG, 1,270 | 61.5 | 63.5 | 60.6 | 62.1 | 75.4 | 75.5 | 81.4 | 81.5 | fails (major +27.0, minor -9.9 against the bar) |
| small convolutional model | real only, leaned to 65 percent minor after training | MTG, 1,270 | 62.8 | 53.9 | 66.6 | 60.3 | 76.9 | 75.2 | 73.0 | 87.9 | fails (major +17.4, minor -3.9 against the bar) |
| small convolutional model | real only, leaned to 70 percent minor after training | MTG, 1,270 | 63.7 | 49.5 | 69.9 | 59.7 | 77.9 | 75.0 | 68.5 | 91.7 | fails (major +13.0, minor -0.7 against the bar) |
| small convolutional model | real only, leaned to 85 percent minor after training | MTG, 1,270 | 62.8 | 33.4 | 75.7 | 54.5 | 76.6 | 73.9 | 52.0 | 96.8 | fails (major -3.0, minor +5.1 against the bar) |
| small convolutional model | real (loops, FMAK songs, Clavier) + 0 % made-up (stopped at pass 60, real validation 67.6) | GiantSteps+, 468 | 80.1 | 67.2 | 82.0 | 74.6 | 88.9 | 84.0 | 92.9 | 95.7 |  |
| small convolutional model | real only, leaned to 65 percent minor after training | GiantSteps+, 468 | 81.4 | 63.8 | 83.9 | 73.8 | 89.3 | 85.3 | 88.1 | 96.4 |  |
| small convolutional model | real only, leaned to 70 percent minor after training | GiantSteps+, 468 | 83.3 | 62.1 | 86.3 | 74.2 | 91.0 | 86.1 | 87.8 | 97.8 |  |
| small convolutional model | real only, leaned to 85 percent minor after training | GiantSteps+, 468 | 85.0 | 51.7 | 89.8 | 70.7 | 92.5 | 86.5 | 81.1 | 100.0 |  |
| small convolutional model | real (loops, FMAK songs, Clavier) + 0 % made-up (stopped at pass 60, real validation 67.6) | GiantSteps Key, 604 | 63.1 | 41.9 | 66.9 | 54.4 | 77.5 | 69.7 | 70.9 | 93.4 |  |
| small convolutional model | real only, leaned to 65 percent minor after training | GiantSteps Key, 604 | 64.1 | 37.6 | 68.9 | 53.3 | 78.1 | 70.0 | 66.0 | 95.1 |  |
| small convolutional model | real only, leaned to 70 percent minor after training | GiantSteps Key, 604 | 65.2 | 35.5 | 70.6 | 53.1 | 79.3 | 70.9 | 62.3 | 96.3 |  |
| small convolutional model | real only, leaned to 85 percent minor after training | GiantSteps Key, 604 | 68.4 | 31.2 | 75.1 | 53.2 | 81.3 | 72.2 | 58.0 | 99.5 |  |
| small convolutional model | real (loops, FMAK songs, Clavier) + 25 % made-up (stopped at pass 88, real validation 66.0) | MTG, 1,270 | 60.8 | 58.8 | 61.7 | 60.2 | 75.3 | 74.3 | 78.0 | 83.6 | fails (major +22.4, minor -8.9 against the bar) |
| small convolutional model | real (loops, FMAK songs, Clavier) + 25 % made-up (stopped at pass 88, real validation 66.0) | GiantSteps+, 468 | 80.1 | 63.8 | 82.4 | 73.1 | 88.7 | 84.4 | 92.5 | 95.2 |  |
| small convolutional model | real (loops, FMAK songs, Clavier) + 25 % made-up (stopped at pass 88, real validation 66.0) | GiantSteps Key, 604 | 63.2 | 39.8 | 67.5 | 53.6 | 78.1 | 69.7 | 71.2 | 93.5 |  |
| small convolutional model | real (loops, FMAK songs, Clavier) + 100 % made-up (stopped at pass 100, real validation 51.6) | MTG, 1,270 | 48.3 | 50.0 | 47.5 | 48.8 | 63.5 | 67.7 | 85.4 | 66.2 | fails (major +13.5, minor -23.1 against the bar) |
| small convolutional model | real (loops, FMAK songs, Clavier) + 100 % made-up (stopped at pass 100, real validation 51.6) | GiantSteps+, 468 | 71.2 | 53.4 | 73.7 | 63.6 | 84.0 | 78.2 | 93.9 | 90.7 |  |
| small convolutional model | real (loops, FMAK songs, Clavier) + 100 % made-up (stopped at pass 100, real validation 51.6) | GiantSteps Key, 604 | 56.5 | 31.2 | 61.1 | 46.1 | 71.4 | 66.4 | 67.4 | 87.2 |  |

**Drift on MTG, convolutional model**: clips right with no made-up music and wrong with it

| made-up share | lost: fifth | relative | parallel | other | lost in all | gained | net |
|---|---:|---:|---:|---:|---:|---:|---:|
| 25 % | 15 | 16 | 31 | 14 | 76 | 67 | -9 |
| 100 % | 42 | 42 | 123 | 70 | 277 | 109 | -168 |
