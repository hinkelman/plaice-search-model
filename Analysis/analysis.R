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
         PreyDensity = PreyNumber / grid_area,
         x = ifelse(Group == "A", Homogeneity, PreyDensity))

files <- list.files("Results", pattern = "\\.csv$", full.names = TRUE)
if (length(files) == 0) stop("No BehaviorSpace output found in Results/")

runs <- lapply(files, read_csv, skip = 6, show_col_types = FALSE) |>
  bind_rows() |>
  select(Scenario = scenario, Tactic = `search-tactic`, Radius = `response-radius`,
         RegenerationTime = `regeneration-time`,
         Captured = `sum [prey-captured] of predators`) |>
  mutate(Tactic = ifelse(Tactic == "local-density",
                         paste0("local-density (r = ", Radius, ")"), Tactic))

summ <- runs |>
  group_by(Scenario, Tactic, RegenerationTime) |>
  summarise(Runs = n(), Mean = mean(Captured), SE = sd(Captured) / sqrt(n()),
            .groups = "drop")

rs <- summ |>
  filter(Tactic == "random-sampling") |>
  select(Scenario, RegenerationTime, RSMean = Mean, RSSE = SE)

# efficiency = mean prey captured / mean prey captured by random sampling of same grid
# approximate 95% CI for ratio of means via delta method
eff <- summ |>
  filter(Tactic != "random-sampling") |>
  inner_join(rs, by = c("Scenario", "RegenerationTime")) |>
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
  select(Group, Scenario, PreyNumber, PreyPatchSize, PreySpacing, RegenerationTime, Tactic,
         Runs, MeanCaptured = Mean, RelativeEfficiency, Lower, Upper,
         PaperRelativeEfficiency) |>
  arrange(RegenerationTime, Scenario, Tactic)
write_csv(eff_out, "Analysis/RelativeEfficiency.csv")

rs_out <- summ |>
  filter(Tactic == "random-sampling") |>
  left_join(scenarios, by = "Scenario") |>
  left_join(rename(paper3, PaperPreyCaptured = PreyCaptured), by = "Scenario") |>
  select(Group, Scenario, PreyNumber, PreyPatchSize, PreySpacing, RegenerationTime,
         Runs, MeanCaptured = Mean, SE, PaperPreyCaptured) |>
  arrange(RegenerationTime, Scenario)
write_csv(rs_out, "Analysis/RandomSampling.csv")

# fit statistics: root mean square difference between model and paper
fit <- eff_out |>
  filter(!is.na(PaperRelativeEfficiency)) |>
  group_by(RegenerationTime, Tactic) |>
  summarise(RMSD = sqrt(mean((RelativeEfficiency - PaperRelativeEfficiency)^2)),
            .groups = "drop")
fit_rs <- rs_out |>
  group_by(RegenerationTime) |>
  summarise(RMSD = sqrt(mean((MeanCaptured - PaperPreyCaptured)^2)),
            MeanPctDiff = 100 * mean((MeanCaptured - PaperPreyCaptured) / PaperPreyCaptured))
print(as.data.frame(fit))
print(as.data.frame(fit_rs))

# alternative interpretation: response "radius" values in the paper (9, 4.5) are circle diameters,
# i.e., the paper's r = 9 corresponds to model radius 4.5 and the paper's r = 4.5 to model radius 2.25
diameter_map <- c("local-density (r = 4.5)" = "local-density (r = 9)",
                  "local-density (r = 2.25)" = "local-density (r = 4.5)")
eff_diam <- eff |>
  filter(Tactic %in% names(diameter_map)) |>
  mutate(ModelTactic = Tactic, Tactic = unname(diameter_map[Tactic])) |>
  left_join(rename(paper4, PaperRelativeEfficiency = RelativeEfficiency),
            by = c("Scenario", "Tactic"))
fit_diam <- bind_rows(
  eff_out |> filter(grepl("local-density", Tactic), Tactic != "local-density (r = 2.25)") |>
    mutate(Interpretation = "radius"),
  eff_diam |> mutate(Interpretation = "diameter")) |>
  filter(!is.na(PaperRelativeEfficiency)) |>
  group_by(RegenerationTime, Interpretation, Tactic, Group) |>
  summarise(RMSD = sqrt(mean((RelativeEfficiency - PaperRelativeEfficiency)^2)), .groups = "drop") |>
  pivot_wider(names_from = Group, values_from = RMSD) |>
  arrange(RegenerationTime, Tactic, desc(Interpretation))
write_csv(fit_diam, "Analysis/LocalDensityFit.csv")
print(as.data.frame(fit_diam), digits = 3)

## Figures ------------------------------------------------------------------------------------

regen_lab <- function(x) paste("Regeneration time =", x, "moves")
tactic_levels <- c("extensive-only", "extensive-intensive",
                   "local-density (r = 9)", "local-density (r = 4.5)")
group_lab <- c(A = "(a) Group A: habitat homogeneity", B = "(b) Group B: habitat prey density",
               C = "(c) Group C: habitat prey density", D = "(d) Group D: habitat prey density")

fig3 <- rs_out |>
  mutate(Panel = ifelse(Group == "A", "(a) Habitat homogeneity", "(b) Number of prey"),
         x = ifelse(Group == "A", PreyPatchSize^2 / grid_area, PreyNumber)) |>
  ggplot(aes(x = x, colour = Group, shape = Group)) +
  geom_line(aes(y = MeanCaptured)) +
  geom_point(aes(y = MeanCaptured)) +
  geom_point(aes(y = PaperPreyCaptured), colour = "black", size = 2.5, alpha = 0.6) +
  facet_grid(RegenerationTime ~ Panel, scales = "free_x",
             labeller = labeller(RegenerationTime = regen_lab)) +
  labs(x = NULL, y = "Prey captured per million moves",
       title = "Random sampling (cf. Hill et al. 2003, Fig. 3)",
       subtitle = "Coloured lines = this model; black symbols = values read from published figure") +
  theme_bw()
ggsave("Analysis/Fig3-random-sampling.png", fig3, width = 9, height = 6, dpi = 150)

fig4 <- eff_out |>
  filter(Tactic %in% tactic_levels) |>
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
       y = "Relative efficiency",
       title = "Relative efficiency of search tactics (cf. Hill et al. 2003, Fig. 4)",
       subtitle = "Lines with 95% CI = this model; symbols = values read from published figure") +
  theme_bw() +
  theme(legend.position = "bottom")
ggsave("Analysis/Fig4-relative-efficiency.png", fig4, width = 14, height = 8, dpi = 150)

fig4_diam <- bind_rows(
  eff_out |> filter(Tactic %in% c("extensive-only", "extensive-intensive")),
  eff_diam) |>
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
       y = "Relative efficiency",
       title = "Relative efficiency with response radius interpreted as a diameter",
       subtitle = "Paper's r = 9 compared with model radius 4.5; paper's r = 4.5 with model radius 2.25. Lines with 95% CI = this model; symbols = published values") +
  theme_bw() +
  theme(legend.position = "bottom")
ggsave("Analysis/Fig4-relative-efficiency-diameter.png", fig4_diam, width = 14, height = 8, dpi = 150)
