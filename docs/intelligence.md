# Intelligence methodology

Tessalytics Intelligence turns synchronized TeslaMateApi history into transparent, on-device estimates. It does not upload history to an analytics service and does not claim to provide machine-learning or safety-critical predictions.

## Forecasts

- **Next seven days of travel:** The engine builds a complete 56-day daily series, including zero-distance days, then averages matching weekdays. The shaded chart band reflects historical variation for each weekday.
- **Next likely charge:** The engine uses the median interval between completed charges, excluding intervals shorter than six hours or longer than fourteen days. The prediction advances by that interval until it falls in the future.
- **Next 30-day charging cost:** Reported charging costs from up to sixty recent days are normalized by covered days and projected over thirty days.
- **Typical efficiency:** The median reported consumption across up to ninety recent days reduces the impact of individual outliers.

## Confidence

Confidence is intentionally conservative. It rises with the number of usable observations and falls when day-to-day or charge-interval variability is high. A low-confidence estimate remains visible as an early estimate so the user can understand what data is missing.

## Signals

The first release detects:

- low reported battery while unplugged;
- recent consumption materially above the prior efficiency baseline;
- recent price per kWh materially above the preceding thirty days;
- meaningful price differences between repeatedly used charging locations;
- stale synchronized drive and charging history.

Signals include the detected change and a suggested next check. They should be treated as prompts for investigation, not diagnoses.

## Notifications

Notification permission is requested only after the user enables the feature. Status alerts are evaluated when Tessalytics refreshes the vehicle. Predicted charging completion is scheduled as a local notification so it can fire after the app closes. Analytical anomaly notifications are deduplicated by a local fingerprint.

All notification preferences and deduplication state remain on the device.
