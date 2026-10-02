# Summarize BehaviorSpace output and compare with Hill et al. (2003) Figs 3 and 4
# Usage (from repo root): Rscript Analysis/analysis.R

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})

grid_area <- 70^2

scenarios <- read_csv("InputData/Scenarios.csv", show_col_types = FALSE) |>
  mutate(Homogeneity = PreyPatchSize^2 / grid_area,
         PreyDensity = PreyNumber / grid_area)

files <- list.files("Results", pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) stop("No BehaviorSpace output found in Results/")

read_results <- function(f) {
  d <- read_csv(f, skip = 6, show_col_types = FALSE)
  # experiments run before enforce-spacing? was added always enforced spacing
  if (!"enforce-spacing?" %in% names(d)) d$`enforce-spacing?` <- TRUE
  d
}

runs <- lapply(files, read_results) |>
  bind_rows() |>
  select(Scenario = scenario, Tactic = `search-tactic`, Radius = `response-radius`,
         RegenerationTime = `regeneration-time`, EnforceSpacing = `enforce-spacing?`,
         Captured = `sum [prey-captured] of predators`) |>
  mutate(Tactic = ifelse(Tactic == "local-density",
                         paste0("local-density (r = ", Radius, ")"), Tactic),
         Spacing = ifelse(EnforceSpacing, "enforced", "off")) |>
  select(-Radius, -EnforceSpacing)

# the spacing switch has no effect on scenarios with zero prey spacing, so the no-spacing
# experiments only include scenarios with nonzero spacing; reuse the other scenarios here
zero_spacing <- scenarios$Scenario[scenarios$PreySpacing == 0]
if (any(runs$Spacing == "off")) {
  runs <- bind_rows(runs,
                    runs |> filter(Spacing == "enforced", Scenario %in% zero_spacing) |>
                      mutate(Spacing = "off"))
}

summ <- runs |>
  group_by(Spacing, Scenario, Tactic, RegenerationTime) |>
  summarise(Runs = n(), Mean = mean(Captured), SE = sd(Captured) / sqrt(n()),
            .groups = "drop")

rs <- summ |>
  filter(Tactic == "random-sampling") |>
  select(Spacing, Scenario, RegenerationTime, RSMean = Mean, RSSE = SE)

# efficiency = mean prey captured / mean prey captured by random sampling of same grid
# approximate 95% CI for ratio of means via delta method
eff <- summ |>
  filter(Tactic != "random-sampling") |>
  inner_join(rs, by = c("Spacing", "Scenario", "RegenerationTime")) |>
  mutate(RelativeEfficiency = Mean / RSMean,
         RelSE = RelativeEfficiency * sqrt((SE / Mean)^2 + (RSSE / RSMean)^2),
         Lower = RelativeEfficiency - 1.96 * RelSE,
         Upper = RelativeEfficiency + 1.96 * RelSE) |>
  left_join(scenarios, by = "Scenario")

paper3 <- read_csv("Analysis/PaperFig3.csv", show_col_types = FALSE)
paper4 <- read_csv("Analysis/PaperFig4.csv", show_col_types = FALSE)

eff_out <- eff |>
  left_join(rename(paper4, PaperRelativeEfficiency = RelativeEfficiency),
            by = c("Scenario", "Tactic")) |>
  select(Spacing, Group, Scenario, PreyNumber, PreyPatchSize, PreySpacing, RegenerationTime,
         Tactic, Runs, MeanCaptured = Mean, RelativeEfficiency, Lower, Upper,
         PaperRelativeEfficiency) |>
  arrange(Spacing, RegenerationTime, Scenario, Tactic)
write_csv(eff_out, "Analysis/RelativeEfficiency.csv")

rs_out <- summ |>
  filter(Tactic == "random-sampling") |>
  left_join(scenarios, by = "Scenario") |>
  left_join(rename(paper3, PaperPreyCaptured = PreyCaptured), by = "Scenario") |>
  select(Spacing, Group, Scenario, PreyNumber, PreyPatchSize, PreySpacing, RegenerationTime,
         Runs, MeanCaptured = Mean, SE, PaperPreyCaptured) |>
  arrange(Spacing, RegenerationTime, Scenario)
write_csv(rs_out, "Analysis/RandomSampling.csv")

# alternative interpretation: response "radius" values in the paper (9, 4.5) are circle diameters,
# i.e., the paper's r = 9 corresponds to model radius 4.5 and the paper's r = 4.5 to model radius 2.25
diameter_map <- c("local-density (r = 4.5)" = "local-density (r = 9)",
                  "local-density (r = 2.25)" = "local-density (r = 4.5)")
eff_diam <- eff_out |>
  filter(Tactic %in% names(diameter_map)) |>
  mutate(Tactic = unname(diameter_map[Tactic])) |>
  select(-PaperRelativeEfficiency) |>
  left_join(rename(paper4, PaperRelativeEfficiency = RelativeEfficiency),
            by = c("Scenario", "Tactic"))

## Fit to published values -------------------------------------------------------------------

rmsd <- function(x, y) sqrt(mean((x - y)^2))

fit_rs <- rs_out |>
  group_by(Spacing, RegenerationTime) |>
  summarise(MeanAbsPctDiff = mean(abs(100 * (MeanCaptured - PaperPreyCaptured) / PaperPreyCaptured)),
            MeanPctDiff = mean(100 * (MeanCaptured - PaperPreyCaptured) / PaperPreyCaptured),
            .groups = "drop")
write_csv(fit_rs, "Analysis/FitRandomSampling.csv")
print(as.data.frame(fit_rs), digits = 3)

fit <- bind_rows(
  eff_out |> filter(Tactic != "local-density (r = 2.25)") |> mutate(Interpretation = "radius"),
  eff_diam |> mutate(Interpretation = "diameter")) |>
  filter(!is.na(PaperRelativeEfficiency))
fit_group <- fit |>
  group_by(Spacing, RegenerationTime, Interpretation, Tactic, Group) |>
  summarise(RMSD = rmsd(RelativeEfficiency, PaperRelativeEfficiency), .groups = "drop") |>
  pivot_wider(names_from = Group, values_from = RMSD)
fit_all <- fit |>
  group_by(Spacing, RegenerationTime, Interpretation, Tactic) |>
  summarise(All = rmsd(RelativeEfficiency, PaperRelativeEfficiency), .groups = "drop")
fit_out <- left_join(fit_group, fit_all,
                     by = c("Spacing", "RegenerationTime", "Interpretation", "Tactic")) |>
  arrange(RegenerationTime, Tactic, Interpretation, Spacing)
write_csv(fit_out, "Analysis/FitRelativeEfficiency.csv")
print(as.data.frame(fit_out), digits = 2)

## Figures ------------------------------------------------------------------------------------

regen_lab <- function(x) paste("Regeneration time =", x, "moves")
tactic_levels <- c("extensive-only", "extensive-intensive",
                   "local-density (r = 9)", "local-density (r = 4.5)")
group_lab <- c(A = "(a) Group A: habitat homogeneity", B = "(b) Group B: habitat prey density",
               C = "(c) Group C: habitat prey density", D = "(d) Group D: habitat prey density")
spacing_lab <- c(enforced = "prey spacing enforced", off = "no prey spacing")
suffix <- c(enforced = "", off = "-no-spacing")

plot_fig3 <- function(sp) {
  p <- rs_out |>
    filter(Spacing == sp) |>
    mutate(Panel = ifelse(Group == "A", "(a) Habitat homogeneity", "(b) Number of prey"),
           x = ifelse(Group == "A", PreyPatchSize^2 / grid_area, PreyNumber)) |>
    ggplot(aes(x = x, colour = Group, shape = Group)) +
    geom_line(aes(y = MeanCaptured)) +
    geom_point(aes(y = MeanCaptured)) +
    geom_point(aes(y = PaperPreyCaptured), colour = "black", size = 2.5, alpha = 0.6) +
    facet_grid(RegenerationTime ~ Panel, scales = "free_x",
               labeller = labeller(RegenerationTime = regen_lab)) +
    labs(x = NULL, y = "Prey captured per million moves",
         title = paste0("Random sampling, ", spacing_lab[sp], " (cf. Hill et al. 2003, Fig. 3)"),
         subtitle = "Coloured lines = this model; black symbols = values read from published figure") +
    theme_bw()
  ggsave(paste0("Analysis/Fig3-random-sampling", suffix[sp], ".png"), p,
         width = 9, height = 6, dpi = 150)
}

plot_fig4 <- function(d, sp, title, subtitle, file) {
  p <- d |>
    filter(Spacing == sp, Tactic %in% tactic_levels) |>
    mutate(Tactic = factor(Tactic, levels = tactic_levels),
           x = ifelse(Group == "A", PreyPatchSize^2 / grid_area, PreyNumber / grid_area)) |>
    ggplot(aes(x = x, colour = Tactic, shape = Tactic)) +
    geom_hline(yintercept = 1, linetype = "dashed", colour = "grey50") +
    geom_line(aes(y = RelativeEfficiency)) +
    geom_errorbar(aes(ymin = Lower, ymax = Upper), width = 0) +
    geom_point(aes(y = PaperRelativeEfficiency), size = 2.5, alpha = 0.8, stroke = 1) +
    scale_shape_manual(values = c(1, 15, 17, 4)) +
    facet_grid(RegenerationTime ~ Group, scales = "free_x",
               labeller = labeller(RegenerationTime = regen_lab, Group = group_lab)) +
    labs(x = "Habitat homogeneity (group A) or habitat prey density (prey per grid unit²; groups B-D)",
         y = "Relative efficiency", title = title, subtitle = subtitle) +
    theme_bw() +
    theme(legend.position = "bottom")
  ggsave(file, p, width = 14, height = 8, dpi = 150)
}

for (sp in unique(rs_out$Spacing)) {
  plot_fig3(sp)
  plot_fig4(eff_out, sp,
            title = paste0("Relative efficiency of search tactics, ", spacing_lab[sp],
                           " (cf. Hill et al. 2003, Fig. 4)"),
            subtitle = "Lines with 95% CI = this model; symbols = values read from published figure",
            file = paste0("Analysis/Fig4-relative-efficiency", suffix[sp], ".png"))
  if (any(eff_diam$Spacing == sp)) {
    plot_fig4(bind_rows(eff_out |> filter(Tactic %in% c("extensive-only", "extensive-intensive")),
                        eff_diam), sp,
              title = paste0("Relative efficiency with response radius interpreted as a diameter, ",
                             spacing_lab[sp]),
              subtitle = "Paper's r = 9 compared with model radius 4.5; paper's r = 4.5 with model radius 2.25. Lines with 95% CI = this model; symbols = published values",
              file = paste0("Analysis/Fig4-relative-efficiency-diameter", suffix[sp], ".png"))
  }
}
