# QuitNic product improvement audit

Hands-on/code audit started 7 August 2026. This is a living implementation ledger,
not a release claim. `Done` requires a code change plus proportionate verification;
`Gate` requires a real device, external service, clinician, or human tester.

## Navigation and information architecture

1. [x] Add horizontal swipe between Today and Journey.
2. [x] Keep vertical Journey scrolling from triggering tab changes.
3. [x] Add a short, interruptible tab transition.
4. [x] Give the selected tab more than colour as a state cue.
5. [x] Increase the unselected tab contrast.
6. [x] Preserve Journey scroll position while switching tabs.
7. [x] Preserve Today state when dismissing a modal.
8. [x] Prevent rapid repeated taps from presenting duplicate sheets.
9. [x] Make every full-screen flow expose a consistent Close control.
10. [x] Prevent interactive dismissal from bypassing unfinished-log Keep/Discard choices.
11. [x] Remove stale five-tab terminology and identifiers everywhere.
12. [ ] Make deep links land on the intended tab and state.
13. [ ] Restore focus to the launching control after dismissing a modal.
14. [x] Add haptic feedback only when a tab actually changes.
15. [x] Keep the tab bar clear of long/expanded Journey content.

## Today

16. [ ] Reduce competition between the hero, craving, Coach, and Quick Log actions.
17. [x] Make the craving action the unmistakable primary action.
18. [x] Explain the difference between Rescue and Quick Log in one line.
19. [x] Replace duplicate progress numbers in the accessibility tree.
20. [x] Turn the next milestone into a tappable Journey shortcut.
21. [x] Show the next milestone name, not only its countdown.
22. [x] Add a useful first-day empty state.
23. [x] Add a useful no-check-in history state.
24. [x] Show the last helpful coping action on Today.
25. [x] Surface offline/sync state without alarming language.
26. [x] Add a compact weekly check-in rhythm indicator.
27. [x] Celebrate logging consistency without encouraging compulsive logging.
28. [x] Avoid implying saved money is exact after incomplete consumption data.
29. [x] Explain current-streak savings after a slip.
30. [x] Make the latest check-in card obviously tappable.
31. [x] Add edit/delete affordances in check-in history.
32. [x] Add an undo window after a non-slip log.
33. [x] Avoid overlaying controls on visually busy landscape details.
34. [x] Reduce visual noise from grain on text-heavy areas.
35. [x] Stop decorative images from appearing in VoiceOver.

## Journey

36. [x] Replace grey/translucent cards with a more energetic progress palette.
37. [x] Add a visible progress rail connecting milestones.
38. [x] Distinguish reached, next, and future states by shape and icon as well as colour.
39. [x] Show percentage/progress to the next checkpoint.
40. [x] Make the next checkpoint feel achievable rather than clinical.
41. [x] Add a positive reached-state microinteraction.
42. [x] Keep the hero art secondary to readable progress.
43. [x] Reduce the hero height at accessibility text sizes.
44. [x] Remove repeated information between the next feature and its roadmap row.
45. [x] Use human countdowns in visible copy and VoiceOver.
46. [x] Refresh countdowns at the precision the remaining duration requires.
47. [x] Pause countdown work when Journey is not visible.
48. [x] Give every disclosure row a minimum 44-point hit target.
49. [x] Make the full row disclose, not only the chevron area.
50. [x] Animate disclosure without moving content under the tab bar.
51. [x] Preserve expanded milestone state across brief tab changes.
52. [x] Add a “why this matters” label separate from symptom predictions.
53. [x] Keep long guidance on an opaque reading surface.
54. [x] Add a direct Rescue action from a difficult early milestone.
55. [x] Make end-of-roadmap state useful after two months.
56. [x] Avoid implying recovery stops at two months.
57. [x] Make cigarette-only claims impossible for vape/pouch/Other plans.
58. [x] Add content-version metadata for medical copy.
59. [ ] Add clinician approval metadata before release.
60. [x] Remove unused zoom-world navigation code after migration.

## Craving logging and history

61. [x] Make Quick Log open instantly and reliably.
62. [x] Explain the neutral default intensity instead of silently choosing 5.
63. [x] Let an accidental craving tap return immediately.
64. [x] Keep Close in the same place across breathing, reflection, and completion.
65. [x] Offer Quick Log throughout Rescue.
66. [x] Make trigger choices feel neutral, not judgemental.
67. [x] Support a custom Other trigger.
68. [x] Allow saving without inventing an “Other” trigger.
69. [x] Reduce the number of decisions required after a craving.
70. [x] Remember recent triggers for faster repeat logging.
71. [x] Remember recent coping actions for faster repeat logging.
72. [x] Add a one-tap “same as last time” path.
73. [x] Show immediate Today feedback after save.
74. [x] Show immediate Journey feedback after a slip.
75. [x] Keep slip completion long enough for Undo.
76. [x] Make non-slip completion brief and encouraging.
77. [x] Avoid confetti/rewards that could trivialise a difficult moment.
78. [x] Show useful pattern insight after enough logs exist.
79. [x] Do not fabricate insights from one or two logs.
80. [x] Add day/week filters to history.
81. [x] Add accessible intensity wording, not only a number.
82. [x] Make selected choices visible without relying on colour.
83. [x] Ensure large text does not hide the Save control.
84. [x] Make the keyboard dismiss without losing entered notes.
85. [x] Preserve an in-progress log across an interruption.
86. [x] Prevent duplicate check-ins from repeated Save taps.
87. [x] Make offline save status explicit and calm.
88. [x] Retry sync without blocking dismissal.
89. [x] Cancel the matching pending operation when Undo is used.
90. [x] Add edit and correction support for accidental wrong outcomes.

## Coach and Rescue

91. [x] Give Coach and Rescue the same visual tokens and toolbar structure.
92. [x] Make Coach open without waiting on server work.
93. [x] Fetch notification/auth/network state after presentation, not before it.
94. [x] Explain Coach’s scope before the first message.
95. [x] Keep urgent-language guidance deterministic and prominent.
96. [x] Never present Coach as medical care.
97. [x] Add useful prompt chips that send immediately.
98. [x] Make retry/reconnect states distinct.
99. [x] Preserve a draft when Coach is dismissed.
100. [x] Keep the composer above the keyboard at accessibility sizes.
101. [x] Give push-to-talk a real accessibility action and state.
102. [x] Explain on-device versus cloud transcription at the choice point.
103. [x] Stop recording automatically on interruption/backgrounding.
104. [x] Keep audio-size rejection local and understandable.
105. [x] Avoid indefinite pulsing animations under Reduce Motion.
106. [x] Respect Reduce Motion in the Rescue depth sequence.
107. [x] Provide an immediate static breathing alternative.
108. [x] Keep the breathing duration expectation visible.
109. [x] Let VoiceOver skip decorative depth narration.
110. [x] Add a direct Coach-to-Rescue handoff without presentation races.

## Settings, onboarding, accessibility, and performance

111. [x] Make Settings present immediately from a lightweight shell.
112. [x] Stop Settings from querying every check-in just to find the last slip.
113. [x] Fetch notification permission after the sheet animation settles.
114. [x] Move developer API controls out of the normal Settings hierarchy.
115. [x] Group destructive controls away from everyday preferences.
116. [x] Explain local versus server deletion in plain language.
117. [x] Always delete local data even when the server is offline.
118. [x] Retry pending server deletion without resurrecting local content.
119. [x] Show the chosen typeface as an accessibility value.
120. [x] Use one canonical type scale and colour-token system.
121. [x] Keep typeface choice separate from text-size accessibility.
122. [x] Remove forced rounded fonts that override the chosen typeface.
123. [x] Ensure every secondary text token passes contrast.
124. [x] Avoid translucent material beneath long reading copy.
125. [x] Keep onboarding’s primary action clear of partially visible rows.
126. [x] Do not request notification permission by default.
127. [x] Make all nicotine types available during onboarding and editing.
128. [x] Explain units and cost entry for pouches.
129. [x] Validate zero/negative costs and impossible daily amounts.
130. [x] Keep onboarding useful offline.
131. [x] Delete the 611-line procedural fallback and keep the asset renderer focused.
132. [x] Split the craving flow into coordinator, reusable form controls, history editor, and breathing-stage presentation.
133. [x] Split Coach voice capture into a focused component, leaving conversation UI separate.
134. [x] Split 436-line `SettingsView` into focused settings sections.
135. [x] Replace broad dashboard and streak queries with fetch limits or aggregate state.
136. [x] Avoid duplicate foreground sync work on first launch.
137. [x] Coalesce notification rescheduling after rapid changes.
138. [x] Cancel screen tasks promptly when their view disappears.
139. [x] Move expensive formatting out of repeatedly evaluated view bodies.
140. [x] Add signposts for Settings presentation and first render.
141. [x] Add a launch-to-interactive performance test.
142. [x] Add a Settings tap-to-first-render performance test.
143. [x] Add a Quick Log tap-to-form performance test.
144. [x] Add a Journey scroll hitch test with all rows expanded.
145. [x] Test Today → log → save → Today/Journey offline and after relaunch.
146. [ ] Test notification denied, allowed, timezone-change, and delivery on device.
147. [ ] Test VoiceOver focus order on every primary flow.
148. [x] Test accessibility XXXL with keyboard and sheets present.
149. [ ] Verify the Release endpoint and full account lifecycle on a physical device.
150. [ ] Run a small human usability test before App Store submission.
151. [x] Remove the Swift 6 mutable-Sendable warning from the locked test token store.
152. [x] Measure image decode and resident memory for the six re-encoded Horizon plates.
153. [x] Re-encode opaque Horizon plates for device delivery where quality permits.
154. [x] Avoid decoding the next landscape plate until a transition can become visible.
155. [x] Replace the two-tap QuitNic menu with a direct 44-point Settings button.
156. [x] Put Today utilities on an opaque dock instead of across the house artwork.
157. [x] Include the milestone name in Today’s next-landmark link.
158. [x] Reduce the oversized first-hour counter on compact-height devices.
159. [ ] Verify Today’s support dock in landscape orientation.
160. [ ] Add snapshot coverage for every Horizon plate at light/dark time grades.

## `musorka` design-language alignment

161. [x] Inventory the full reference folder rather than treating one landscape as the brief.
162. [x] Extract a canonical cobalt, ivory, vermillion, forest, and plum palette.
163. [x] Replace generic translucent Journey surfaces with saturated print colours.
164. [x] Use an ivory editorial feature card for the next checkpoint.
165. [x] Tighten the shared card and primary-button radii.
166. [x] Make Quick Log lead with a bold editorial headline rather than form copy.
167. [x] Give repeat logging a visually distinct forest shortcut.
168. [x] Establish one spacing scale and remove screen-local magic numbers.
169. [x] Establish one radius scale instead of literal radii across views.
170. [x] Establish one border-weight scale for cards, chips, and controls.
171. [x] Replace remaining product-surface RGB values with named semantic tokens.
172. [x] Audit every opacity against real art plates, not only gradients.
173. [x] Reduce the number of floating capsules on Today.
174. [ ] Give Today a stronger asymmetrical editorial composition.
175. [x] Keep the landscape visible without placing body copy over detailed terrain.
176. [x] Use one recurring label treatment for eyebrow headings.
177. [x] Use one recurring data-number treatment across Today and Journey.
178. [x] Use serif as an editorial option without forcing it on accessibility text.
179. [x] Preview every typeface choice in Settings before selection.
180. [ ] Validate every typeface at accessibility XXXL.
181. [ ] Replace generic SF Symbol clusters where the art can carry meaning.
182. [x] Keep functional icons familiar even when decorative language is unusual.
183. [x] Give Journey reached states a subtle print-stamp animation.
184. [x] Add a restrained transition between cobalt and forest milestone states.
185. [x] Make Reduce Motion substitutions feel intentional, not merely static.
186. [x] Remove the repeated-card rhythm from Coach conversation chrome.
187. [x] Give Coach an image-led opening state consistent with Horizon.
188. [x] Make Coach prompt chips share Quick Log’s print-label treatment.
189. [x] Give Rescue a static cobalt/ivory breathing alternative.
190. [x] Use the artwork’s red only for action, urgency, and the current waypoint.
191. [x] Avoid using red as a reward colour.
192. [x] Make slip states warm and humane without borrowing success green.
193. [x] Give history an editorial pattern summary rather than a stock settings list.
194. [x] Convert Settings previews to the same palette while keeping native form behaviour.
195. [x] Ensure onboarding introduces the visual world before collecting data.
196. [x] Remove any remaining Horizon art with web-overlay text or generation artefacts.
197. [x] Document approved source assets, crop rules, and focal points.
198. [x] Re-encode delivery art while preserving visible grain at device scale.
199. [ ] Add visual regression references derived from the approved `musorka` moodboard.
200. [ ] Run a five-person adjective test: vivid, calm, hopeful, clear, trustworthy.

## App Store submission hygiene

201. [x] Add a privacy manifest for required-reason APIs and collected data.
202. [x] Document the exact App Store privacy-label categories implied by the app.
203. [ ] Validate the archived app's generated privacy report in Xcode Organizer.
204. [x] Declare operating-system-only encryption for App Store export compliance.
205. [x] Replace the legacy generic wellness icon with the canonical Horizon landscape mark.
206. [x] Give the system launch screen the canonical deep-cobalt background instead of a white flash.
207. [x] Bound foreground outbox recovery and delivery fetches to one work budget.
208. [x] Batch offline check-in encoding instead of creating one detached task per record.
209. [x] Defer Journey construction until its first visit while preserving later state.
210. [x] Debounce Coach draft persistence and release its Markdown cache on tab exit.
211. [x] Allocate the Coach audio engine only during an active recording.
212. [x] Replace full-history slip lookups with one-row predicate queries.
213. [x] Add deterministic 500/5,000-record and 1,000-message performance fixtures.
214. [x] Measure populated Journey and long-transcript Coach first render with app signposts.
215. [x] Gate repeated tab switching and background/foreground recovery with three-sample budgets.
216. [x] Prove 5,000-record Today memory growth stays below 2 MiB.
217. [x] Measure Coach peak and five-second recovery, with explicit release and residual gates.
218. [x] Run Time Profiler and Allocations traces before accepting further micro-optimizations.
219. [x] Revert savings-cache, Markdown fast-path, and smaller transcript-window experiments that did not beat noise.
220. [x] Make “Keep for later” survive dismissal and process death instead of losing the draft with its transient scene.
221. [ ] Repeat Release launch, memory, scroll, and Coach recovery on the oldest supported physical iPhone.
222. [ ] Collect MetricKit launch, hang, and memory diagnostics from a TestFlight cohort.
