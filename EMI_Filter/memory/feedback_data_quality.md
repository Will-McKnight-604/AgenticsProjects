---
name: feedback_data_quality
description: When digitizer accuracy is limited by input data quality (sub-pixel resolution), flag and ask for manual review rather than spending time tuning
type: feedback
---

When the CV digitizer can't achieve acceptable accuracy due to input data limitations (e.g., curve values too small relative to y-axis scale, resulting in sub-pixel resolution), do NOT spend time trying to tune the algorithm. Instead:
1. Flag the material with a data quality warning
2. Highlight the problematic region of the image
3. Generate a comparison plot showing where errors are high
4. Ask for manual approval — if not approved, the pipeline user needs to find better source data
