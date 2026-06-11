## ADDED Requirements

### Requirement: Generate a search-term report for a campaign

The app SHALL fetch a Sponsored Products search-term report (`spSearchTerm`) for a selected campaign and active profile via the async report pipeline, decoding each row's search term, clicks, spend, sales, and orders.

#### Scenario: Search-term report fetched

- **WHEN** the user starts harvesting for a campaign
- **THEN** the app requests, polls, downloads, and decodes that campaign's search-term report scoped to the active profile

#### Scenario: No search-term data

- **WHEN** the report returns no search terms
- **THEN** the app SHALL show an empty state explaining the campaign has no search-term activity yet, not an error

### Requirement: Score search terms into graduate and negate buckets

The app SHALL classify each search term using user-tunable criteria, pre-filled with defaults: **graduate** when orders ≥ a threshold, clicks ≥ a threshold, and ACOS ≤ a target; **negate** when clicks ≥ a threshold and orders are zero. Changing a criterion SHALL re-classify the list.

#### Scenario: Default criteria applied

- **WHEN** the report loads
- **THEN** terms are bucketed using the default thresholds, and each bucket shows its matching terms with spend, sales, orders, and ACOS

#### Scenario: Adjusting criteria re-buckets

- **WHEN** the user changes a threshold (e.g. minimum orders)
- **THEN** the graduate/negate buckets recompute immediately from the same report data, without refetching

### Requirement: Review and approve before any change

The app SHALL require explicit review and confirmation before writing anything: the user selects which terms to act on and the target Manual-Exact campaign/ad group, and the app SHALL summarize exactly what will be created and negated before proceeding.

#### Scenario: User selects terms and target

- **WHEN** the user is in the review step
- **THEN** the user can check/uncheck individual terms and choose an existing manual campaign/ad group as the graduation target

#### Scenario: Confirmation summary

- **WHEN** the user proceeds from review
- **THEN** the app SHALL present a summary ("create N exact keywords in <target>, negate N terms in <auto campaign>") and act only after explicit confirmation

#### Scenario: Nothing selected

- **WHEN** no terms are checked
- **THEN** the confirm action is disabled

### Requirement: Graduate winners and negate in the source

On confirmation, the app SHALL create the selected terms as exact-match keywords in the chosen manual ad group, and create them as negative-exact keywords in the source (auto) campaign, scoped to the active profile.

#### Scenario: Graduation writes both sides

- **WHEN** the user confirms graduation of a set of terms
- **THEN** the app creates exact keywords in the target manual ad group and negative-exact keywords against the source campaign

#### Scenario: Negate-only selection

- **WHEN** the user selected terms only from the negate bucket
- **THEN** the app creates only negative-exact keywords in the source campaign and creates no manual keywords

### Requirement: Per-term result reporting

The app SHALL report the outcome of each attempted write per term — added, negated, skipped because it already exists (duplicate), or failed — and SHALL NOT treat a duplicate or a partial batch failure as a total failure.

#### Scenario: Mixed outcomes

- **WHEN** a batch contains new terms, an already-existing keyword, and one rejected by the API
- **THEN** the app shows each term's individual outcome and a summary count, leaving successful writes applied

#### Scenario: Already-exists is not an error

- **WHEN** a term being graduated already exists as a keyword in the target
- **THEN** the app SHALL mark it "already added" rather than failing the operation
