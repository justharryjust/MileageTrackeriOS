# Tax Rules by Jurisdiction — Rules of Record

The detailed, per-country compliance rules for the 16 supported jurisdictions. Rate figures are audited separately in [`mileage-rates-by-country.md`](mileage-rates-by-country.md); the compliance gap-analysis (what the app supports vs. these rules) is in [`tax-compliance-audit.md`](tax-compliance-audit.md). **This file is the rules-of-record per country** — the tickets tracking each gap point here.

The app's purpose is to make it **possible/easy** to be compliant, not to enforce compliance. Figures below were verified against official sources; where a value is a caveat or uncertainty it is kept as written.

---

## 🇺🇸 United States (US)

- **Permitted methods:** Standard mileage rate (flat) **or** actual car expenses. For an owned car you must **elect the standard rate in the first year**, then may switch either way in later years. Standard rate is **disallowed** if you operate 5+ cars simultaneously, took a Section 179 deduction, or used non-straight-line depreciation.
- **Logbook requirement:** Adequate contemporaneous records of **every business trip**. No sample period, no redo interval.
- **Record retention:** Generally **3 years** after filing (depreciation records longer).
- **Required per-trip fields:** Date, business mileage/distance, destination, business purpose.
- **Currency:** USD
- **Notes & caveats:** The first-year election and the 5-or-more-cars disallowance can invalidate a standard-rate claim — worth signposting.
- **Sources:** https://www.irs.gov/taxtopics/tc510 · https://www.irs.gov/publications/p463

## 🇨🇦 Canada (CA)

- **Permitted methods:** **No flat per-km deduction** for the self-employed — the deduction is the business-use **% of actual costs** (fuel, insurance, licence, maintenance, CCA, interest). The 73¢/67¢ per-km figure is an employer→employee **reimbursement** allowance only.
- **Logbook requirement:** Full-year log, **or** keep a 12-month base-year log once then a **3-month sample** in later years (valid while sample-period business use stays within **±10%** of the base year). Record odometer at fiscal-period start/end.
- **Record retention:** **6 years** from the end of the tax year.
- **Required per-trip fields:** Date, destination, purpose, kilometres; plus fiscal start/end odometer.
- **Currency:** CAD
- **Notes & caveats:** The app's "Standard rate" produces a valid **reimbursement** figure for an employee, but **not** a self-employed deduction.
- **Sources:** https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/sole-proprietorships-partnerships/business-expenses/motor-vehicle-expenses/motor-vehicle-records.html

## 🇬🇧 United Kingdom (GB)

- **Permitted methods:** Simplified-expenses flat mileage (self-employed) **or** actual running costs + capital allowances. Once a method is chosen for a vehicle you must keep it for that vehicle.
- **Logbook requirement:** Keep adequate records to identify the **business element** of mileage; per-journey, no prescribed sample period.
- **Record retention:** **5 years** after the 31 January Self Assessment deadline for the tax year.
- **Required per-trip fields:** Date, business miles/distance, journey purpose/destination.
- **Currency:** GBP
- **Notes & caveats:** Method is locked per-vehicle once chosen — the app should not let a user silently switch.
- **Sources:** https://www.gov.uk/expenses-if-youre-self-employed/travel · https://www.gov.uk/self-employed-records/how-long-to-keep-your-records

## 🇳🇿 New Zealand (NZ)

- **Permitted methods:** Kilometre-rate method (flat; Tier One applies to the business portion of the **first 14,000 km** total travel/year, Tier Two beyond) **or** cost method.
- **Logbook requirement:** A test period of **at least 90 consecutive days**; the resulting business-use % is valid **up to 3 years**, unless business use changes by more than **±20%** (then a new 90-day logbook).
- **Record retention:** **7 years**.
- **Required per-trip fields:** Date, distance, reason per business journey; plus odometer at start and end of the 90-day test period.
- **Currency:** NZD
- **Notes & caveats:** This is the model the app's logbook-period feature already implements correctly.
- **Sources:** https://www.ird.govt.nz/income-tax/income-tax-for-businesses-and-organisations/types-of-business-expenses/claiming-vehicle-expenses/use-a-logbook

## 🇦🇺 Australia (AU)

- **Permitted methods:** Cents-per-kilometre method (flat; capped at **5,000 business km/car/year** — above this you **must** use the logbook method) **or** logbook method.
- **Logbook requirement:** Minimum **12 continuous weeks**, representative; valid **5 years**.
- **Record retention:** **5 years** from lodging the return.
- **Required per-trip fields:** Journey start+finish date, odometer start+end per journey, km, purpose; plus period-boundary + annual odometer, business-use %, and car make/model/engine capacity/registration.
- **Currency:** AUD
- **Notes & caveats:** Matches the app's logbook-period model; warn users approaching the 5,000 km crossover where logbook becomes mandatory.
- **Sources:** https://www.ato.gov.au/businesses-and-organisations/income-deductions-and-concessions/income-and-deductions-for-business/deductions/deductions-for-motor-vehicle-expenses/logbook-method

## 🇩🇪 Germany (DE)

- **Permitted methods:** €0.30/km flat for business trips with own car (Dienstreise; accepted without a full Fahrtenbuch but trips must be substantiated) **or** Fahrtenbuch/actual-cost method.
- **Logbook requirement:** Fahrtenbuch — **full-year, every trip**, kept contemporaneously and in closed **tamper-proof** form; electronic logs accepted if business purpose is entered **within 7 days** and entries are tamper-evident. Not a sample period.
- **Record retention:** **10 years** for a Fahrtenbuch substantiating business expenses (§147 AO); ~6 years for employee travel-expense records.
- **Required per-trip fields:** Date, odometer start+end per trip, destination, purpose, **business partner/customer visited**, any detour.
- **Currency:** EUR
- **Notes & caveats:** Business-trip mileage (€0.30/km both directions) is distinct from the commuter Entfernungspauschale (one-way, €0.30 first 20 km / €0.38 from km 21). The app's `commitHash`/`committedAt` supports the tamper-proof, within-7-days standard.
- **Sources:** https://ao.bundesfinanzministerium.de/lsth/2025/B-Anhaenge/Anhang-14/inhalt.html

## 🇦🇹 Austria (AT)

- **Permitted methods:** Amtliches Kilometergeld €0.50/km car (motorcycle/bicycle €0.25/km), tax-free up to **30,000 business km/year** (bicycle 3,000 km) **or** actual costs.
- **Logbook requirement:** A Fahrtenbuch or other suitable records covering **every business trip / the full year** (no sample period).
- **Record retention:** **7 years** after year-end of the last entry (§132 BAO).
- **Required per-trip fields:** Date, odometer/km reading, business km for the day, origin, destination, purpose.
- **Currency:** EUR
- **Notes & caveats:** Track running annual business km to warn at the 30,000 km cap.
- **Sources:** https://www.bmf.gv.at/themen/steuern/kraftfahrzeuge/kilometergeld.html

## 🇨🇭 Switzerland (CH)

- **Permitted methods:** Kilometerentschädigung, accepted maximum **CHF 0.75/km** from 1.1.2026 **or** actual costs. Employer Spesenreglement may set its own rate; not a rigid statutory ceiling.
- **Logbook requirement:** A Fahrtenbuch/Bordbuch is **always required**, kept **daily, complete and gap-free** (contemporaneous, no sample period).
- **Record retention:** **10 years** (Art. 958f OR).
- **Required per-trip fields:** Date, **specific** start and destination location (generic "business" insufficient), purpose, km; cumulative annual km recommended.
- **Currency:** CHF
- **Notes & caveats:** Let the user set a custom per-km rate to match an employer's Spesenreglement, defaulting to CHF 0.75.
- **Sources:** https://spesen-app.ch/wiki/fahrtenbuch-anforderungen-schweiz-spesen · https://www.bdo.ch/de-ch/publikationen/aufbewahrungspflichten-und-aufbewahrungsfristen-von-geschaeftsunterlagen-in-der-schweiz

## 🇧🇪 Belgium (BE)

- **Permitted methods:** Forfaitaire kilometervergoeding flat (~€0.44/km) **or** actual professional costs (werkelijke beroepskosten) — a choice.
- **Logbook requirement:** Must substantiate professional km with supporting evidence; **no gazetted logbook format**, no fixed sample/validity rule.
- **Record retention:** **7 years** (accounting/VAT); up to **10 years** for fraud cases.
- **Required per-trip fields:** (best-practice, not gazetted) Date, origin, destination, distance, business purpose; link to invoices for the actual-cost route.
- **Currency:** EUR
- **Notes & caveats:** No specific logbook format is mandated to current findings.
- **Sources:** https://fin.belgium.be/nl/particulieren/belastingaangifte/inkomsten/vergoedingen-woon-werkverkeer

## 🇳🇱 Netherlands (NL)

- **Permitted methods:** €0.25/km flat for business trips in a private vehicle — this is the **sole method** for a privately-owned car. You may **not** separately deduct fuel/insurance/toll/parking (actual-cost applies only when the vehicle is on the business balance sheet, a different regime).
- **Logbook requirement:** A rittenregistratie (sluitende kilometeradministratie) demonstrating business vs private km; ongoing, no fixed redo cycle for the deduction.
- **Record retention:** **7 years**.
- **Required per-trip fields:** Date, origin/destination (route), distance, business-vs-private character/purpose; odometer start/end enables the stricter <500-km-private logbook.
- **Currency:** EUR
- **Notes & caveats:** Do **not** offer an actual-cost add-on for a privately-owned car — it's disallowed.
- **Sources:** https://www.belastingdienst.nl/wps/wcm/connect/bldcontentnl/belastingdienst/zakelijk/winst/inkomstenbelasting/veranderingen-inkomstenbelasting-2026/zakelijk-gebruik-privevervoermiddel-2026

## 🇪🇸 Spain (ES)

- **Permitted methods:** **No statutory per-km deduction** for self-employed (autónomos); there is a per-km **employee** reimbursement exemption (~€0.26/km, figure moves). Autónomo deduction is via actual costs backed by invoices **and** requires the vehicle to be ~100% **exclusively business** (partial use generally disallowed and hard to prove).
- **Logbook requirement:** Keep a hoja de ruta / registro de kilometraje plus invoices; ongoing, no prescribed period.
- **Record retention:** **4 years** (tax, Ley 58/2003 art. 66); **6 years** commercial (Código de Comercio art. 30).
- **Required per-trip fields:** Date, origin, destination, business purpose, start/end odometer; plus fuel/toll/parking invoices.
- **Currency:** EUR
- **Notes & caveats:** The exclusive-business-use test means many autónomos can't deduct car costs at all — surface this rather than implying a clean per-km deduction.
- **Sources:** https://sede.agenciatributaria.gob.es/Sede/iva/facturacion-registro/facturacion-iva/obligacion-conservar-facturas.html

## 🇸🇪 Sweden (SE)

- **Permitted methods:** Schablon milersättning **25 kr/mil (2.50 kr/km)** for a private car used in business — effectively **mandatory** for a private car (actual-cost only if the car is a business asset).
- **Logbook requirement:** A körjournal is **de facto required**, covering **every business trip** on an ongoing basis (company cars must log private trips too).
- **Record retention:** **7 years** (Bokföringslagen).
- **Required per-trip fields:** Vehicle registration; odometer at year start/end; date and odometer start/end per trip; km (mil) per trip; start+end address; purpose/errand; places/companies/contacts visited.
- **Currency:** SEK
- **Notes & caveats:** Rate is published per "mil" (10 km) — the app stores it per km.
- **Sources:** https://www.skatteverket.se/privat/skatter/arbeteochinkomst/formaner/bilforman/korjournal.4.18e1b10334ebe8bc8000695.html

## 🇳🇴 Norway (NO)

- **Permitted methods:** Tax-free distance allowance **3.50 NOK/km** (same for petrol/diesel/electric) **or** actual costs. A private car driven **≥6,000 business km/year** is treated as a business asset (yrkesbil, actual-cost regime).
- **Logbook requirement:** A kjørebok must **continuously and daily** register professional use; odometer read at least **monthly**; multi-driver cars record who drove.
- **Record retention:** **5 years** after the income year.
- **Required per-trip fields:** Date, starting point, company/site/customer visited, end point, distance (per odometer), purpose; driver identity if multiple.
- **Currency:** NOK
- **Notes & caveats:** Don't conflate the tax-free 3.50 NOK/km with the higher (partly taxable) state-employee travel-agreement rate.
- **Sources:** https://www.skatteetaten.no/en/rates/car-allowance-distance-based-allowance/ · https://www.skatteetaten.no/en/rettskilder/type/uttalelser/prinsipputtalelser/bruk-av-arbeidsgivers-bil---krav-til-dokumentasjon/

## 🇩🇰 Denmark (DK)

- **Permitted methods:** Tax-free kørselsgodtgørelse **3.94 DKK/km up to 20,000 km/year** then **2.28 DKK/km** **or** actual expenses (self-employed may choose).
- **Logbook requirement:** A **contemporaneous, ongoing** kørebog/kørselsregnskab — a log prepared **afterwards is not accepted**; odometer read at start/end of each driving day and the log must reconcile with the odometer.
- **Record retention:** **5 years** after end of the financial year (Bogføringsloven).
- **Required per-trip fields:** (per bekendtgørelse om rejse- og befordringsgodtgørelse) Recipient name, address & CPR number; purpose; date; destination(s) incl. intermediate stops; km driven; rates applied; and the allowance calculation.
- **Currency:** DKK
- **Notes & caveats:** The "no retroactive logs" rule maps directly to the app's contemporaneous `committedAt` timestamp.
- **Sources:** https://skat.dk/en-us/businesses/employees-and-pay/transport-allowance/documentation-and-checking-transport-allowance

## 🇫🇮 Finland (FI)

- **Permitted methods:** Tax-free kilometrikorvaus **0.55 €/km** (also the maximum travel-expense deduction rate for a private car) **or** actual costs for a business-owned car. Without a driving log the deduction may be estimated.
- **Logbook requirement:** An ajopäiväkirja kept from the start of business, **ongoing**, with calendar-month totals split into business vs other driving.
- **Record retention:** **6 years** after the end of the tax year.
- **Required per-trip fields:** Start and end **time**; start and end place; odometer start and end; km driven; **route**; purpose; customer/destination on work trips; plus monthly business/private totals.
- **Currency:** EUR
- **Notes & caveats:** Finland uniquely requires trip **times** and **route**, plus monthly business/private summaries.
- **Sources:** https://www.vero.fi/en/individuals/deductions/kilometre-and-per-diem-allowances/ · https://www.vero.fi/syventavat-vero-ohjeet/paatokset/90150/verohallinnon-paatos-ajoneuvon-kaytosta-pidettavasta-ajopaivakirjasta/

## 🇿🇦 South Africa (ZA)

- **Permitted methods:** (a) simplified prescribed rate **495 c/km (2026/27)** — usable **only** where the employee receives no other travel allowance/advance (parking & tolls excepted); (b) deemed-cost method by **vehicle-value band** (fixed cost + fuel cost + maintenance cost per km); or (c) actual costs. Which applies is driven by whether a travel allowance is received.
- **Logbook requirement:** Effectively **mandatory** — *"Without a logbook you won't be able to claim."* Continuous/contemporaneous covering the **full year of assessment** (1 Mar–28/29 Feb); a **new logbook each tax year** (no multi-year validity); opening & closing odometer for the year recorded; home-to-work is private and **excluded**.
- **Record retention:** **5 years** from submitting the return.
- **Required per-trip fields:** (SARS eLogbook) Date of travel; opening odometer; closing odometer (→ km); business-travel details = where you started, where you went, and the business reason; plus year opening/closing odometer.
- **Currency:** ZAR
- **Notes & caveats:** The strictest jurisdiction — odometer opening/closing is load-bearing, and the logbook resets annually.
- **Sources:** https://www.sars.gov.za/types-of-tax/personal-income-tax/travel-e-log-book/

---

## Cross-jurisdiction patterns

1. **A superset per-trip record** of `{date, odometer start/end, km, origin, destination, purpose, business/private flag, customer/contact visited, trip start/end time}` satisfies the strictest countries (Germany / Denmark / Finland) and is a superset for all the rest.
2. **Only NZ, AU and (loosely) CA use an expiring SAMPLE-period logbook.** All other jurisdictions require **continuous, every-trip** records with no sample window — the single most important structural point for the app's logbook model.
3. **Retention ranges 3–10 years** (US 3; ES 4; AU/GB/NO/DK/ZA 5; CA/FI 6; NZ/AT/SE/BE/NL 7; DE/CH 10), so a **7+ year** default satisfies most.
4. **Contemporaneous-entry / tamper-evidence** is explicitly required by **DE** (within 7 days), **CH** (daily, gap-free) and **DK** (no retroactive logs) — the app's existing `commitHash` + `committedAt` already speaks to this.
