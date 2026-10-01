Replication of the simulation model of saltatory search by juvenile plaice described in [Hill et al. (2003)](https://doi.org/10.1111/j.1095-8649.2003.00212.x).

NetLogo 7.0.4

## Contents

- `plaice-search-model.nlogox`: the model. See its Info tab for a description and implementation notes.
- `InputData/`: prey distribution scenarios (Table I) and cumulative distributions of move length and turn angle digitized from Figs 1 and 2.
- `run-experiments.sh`: runs the BehaviorSpace experiments headlessly and writes the output to `Results/`.
- `Analysis/analysis.R`: summarises `Results/` and compares the output with values read by eye from Figs 3 and 4 of the paper (`Analysis/PaperFig3.csv`, `Analysis/PaperFig4.csv`).

## Reproducing the results

```bash
./run-experiments.sh
```

```bash
Rscript Analysis/analysis.R
```

The full design (4 search tactics, 26 prey distributions, 2 regeneration times, 60 runs of 1,000,000 moves) takes about 5 hours on 8 cores. The R script needs dplyr, tidyr, readr and ggplot2.

## Results

Output from the full design is in `Results/`, summarised in `Analysis/RandomSampling.csv` and `Analysis/RelativeEfficiency.csv`. Relative efficiency is mean prey captured divided by mean prey captured by random sampling of the same grid. Published values were read by eye from the figures, so treat them as accurate to about ±0.01–0.02 (Fig. 4) or ±500 prey (Fig. 3). The natural prey distributions (Table II, Fig. 5) cannot be replicated because the field maps are not available.

![Random sampling](Analysis/Fig3-random-sampling.png)

![Relative efficiency](Analysis/Fig4-relative-efficiency.png)

### Prey regeneration

The paper states that a captured prey item was absent for 1000 predator moves. With that value the model does not reproduce the published random-sampling results (Fig. 3). Captures are on average 35% lower than published, e.g., ~19,000 vs ~31,000 per million moves for 49 prey in the homogeneous habitat. The published values are matched closely (mean difference +2.5%) when prey are not depleted (`regeneration-time` = 1). For 49 prey in a 70 x 70 habitat, 31,000 captures per million moves is almost exactly the no-depletion expectation (49π/4900 ≈ 0.0314 per move).

Fig. 4 points the same way. With a regeneration time of 1000, the extensive–intensive tactic is *less* efficient than random sampling in homogeneous habitats (0.97–0.99 in group D). The paper reports that it is 3–4% *more* efficient. With a regeneration time of 1 it is 1.01–1.05. Shorter regeneration times (10–250 moves) gave no better fit in exploratory runs. **The published results therefore appear to have been produced with little or no prey depletion, despite the stated 1000-move regeneration time.** Both values are included in the experiments.

### Root mean square difference from published relative efficiency

| Tactic | Regeneration = 1 | Regeneration = 1000 |
|---|---|---|
| extensive-only | 0.009 | 0.013 |
| extensive-intensive | 0.023 | 0.148 |
| local-density (r = 9) | 0.091 | 0.160 |
| local-density (r = 4.5) (group A only) | 0.146 | 0.049 |

### Summary

With no prey depletion, the replication reproduces:

- the random-sampling results (Fig. 3);
- extensive-only search being as efficient as random sampling everywhere;
- the extensive–intensive tactic's efficiency in all four groups, closely (e.g., 1.44 vs 1.44 in the most heterogeneous habitat; increasing with prey abundance in groups B and C);
- the local-density tactic (r = 9) being the most efficient tactic in groups B and C, and declining with homogeneity in group A.

It does not reproduce:

- **Local density in small patches (group A).** The paper has local density (r = 9) peaking at intermediate homogeneity and being beaten by extensive–intensive in the most heterogeneous habitat. The model has it highest in the smallest patch (1.52 vs 1.33). Group C local density is also 0.05–0.11 too high.
- **Local density at r = 4.5.** In the paper it is clearly less efficient than r = 9 in heterogeneous habitats. In the model the two radii are nearly identical in group A without depletion.
- **Local density (r = 9) in group D with 20 or more prey.** The model gives ~1.00 vs 1.10–1.17 published. With prey spacing of 7–10 grid units, the circle of radius 9 rarely holds more prey than the threshold (1.0–2.5 prey), so the predator almost never switches to intensive search.

These remaining differences all involve the local-density rule. The paper does not fully specify that rule: when density is assessed relative to capture, how the threshold is computed, or what "compared integer values of prey density" means. Rounding the threshold to the nearest integer was tested and made the fit worse.

