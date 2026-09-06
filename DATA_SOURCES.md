# Data source register

The current application bundles **no external statistical, medical, demographic, or life-expectancy dataset**.

The metric shown as “健康でいたい年齢 / Healthy-age goal” is calculated only from:

- the birth date entered by the user; and
- the target age explicitly accepted or changed by the user during onboarding.

The initial slider position of 75 is a UI starting value, not a population statistic, diagnosis, or prediction. The app does not infer sex, health condition, or mortality risk. The UI and privacy documentation must continue to state this distinction.

The optional “勤務時間 / Work hours” timeline uses start and end times configured by the user and the device’s local date and time. The default 09:00–18:00 schedule is an editable starting value. It repeats daily, supports overnight shifts, and treats matching start and end times as a 24-hour shift. No employer, calendar, attendance, or external work-schedule data is imported or transmitted.

“今週 / This week” follows the device calendar’s week-start setting by default. Users can instead select any weekday. An explicit choice runs from that weekday’s local midnight to the next occurrence’s local midnight; calendar boundaries account for daylight-saving changes instead of assuming every week lasts exactly 168 hours. The preference stays on the device.

If a public dataset is added later, this register must record its title, publisher, jurisdiction, reference year, source URL, retrieval date, license, exact transformation, version, and content hash before the dataset can ship.
