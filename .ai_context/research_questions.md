# Research Questions

## Primary Questions (Driving This Analysis)
1. Which copula family best fits longitudinal education data? → ANSWERED: t-copula
2. Which marginal transformation preserves tail dependence? → ANSWERED: Kernel Gaussian
3. How sensitive are copula parameters to grade span? → IN PROGRESS (STEP_3)
4. How sensitive are copula parameters to sample size? → IN PROGRESS (STEP_3)
5. Does the framework generalize across content areas? → IN PROGRESS (STEP_3)

## Secondary Questions
- Can we extend to 3-way copulas (Grade 4→5→6)?
- Do time-varying copulas improve fit?
- How does IRT-based marginal estimation compare to kernel?

## Resolved Issues
- Frank copula false dominance → FIXED (two-stage transformation approach)
- I-spline with 4 knots → FIXED (increased to 9 knots)
- Non-uniform pseudo-observations → FIXED (use empirical ranks for family selection)

## Open Questions
- Optimal number of bootstrap iterations for production use?
- Best bandwidth selection for kernel smoothing in diverse datasets?
