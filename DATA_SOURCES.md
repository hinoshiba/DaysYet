# Data source register

The current application bundles **no external statistical, medical, demographic, or life-expectancy dataset**.

The metric shown as “健康でいたい年齢 / Healthy-age goal” is calculated only from:

- the birth date entered by the user; and
- the target age explicitly accepted or changed by the user during onboarding.

The initial slider position of 75 is a UI starting value, not a population statistic, diagnosis, or prediction. The app does not infer sex, health condition, or mortality risk. The UI and privacy documentation must continue to state this distinction.

If a public dataset is added later, this register must record its title, publisher, jurisdiction, reference year, source URL, retrieval date, license, exact transformation, version, and content hash before the dataset can ship.
