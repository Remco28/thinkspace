## Findings, ranked by impact

1. **Secondary text is the weakest across the interface.** In [05-nothing-selected-page.png](/home/frank/.cache/review-loop/read-r1/copy/05-nothing-selected-page.png), the page-growth hints are small and pale; similar secondary text appears in the size fields and layer lists in [02-picture-selected.png](/home/frank/.cache/review-loop/read-r1/copy/02-picture-selected.png), [03-text-selected.png](/home/frank/.cache/review-loop/read-r1/copy/03-text-selected.png), and [04-arrow-selected.png](/home/frank/.cache/review-loop/read-r1/copy/04-arrow-selected.png). The hint gray is about **3.5:1** against the panel background; counts and other paler values look closer to **2.6:1**. Those ratios make small text harder to pick out, especially on the ThinkPad.

2. **The default body text is small for a label-heavy app.** Field labels, layer rows, menu items, and ordinary controls are roughly **12–13 px**; their visible letter height is smaller. That is workable on the 24-inch display, but at 100% on the ThinkPad it will look about 40% smaller physically. Using one small size for many different kinds of information also makes it harder for the eye to settle on a priority.

3. **The shortcuts dialog is dense at true size.** In [09-shortcuts.png](/home/frank/.cache/review-loop/read-r1/copy/09-shortcuts.png), the explanations and key labels are around **12 px**, with many rows and some wrapped lines. The text is dark enough, but the amount of small copy makes the dialog slower to scan. The dimmed app behind it is deliberate and isn’t a defect.

4. **The collection instructions and menu shortcuts are faint secondary cases.** The centered instructions in [01-empty-start.png](/home/frank/.cache/review-loop/read-r1/copy/01-empty-start.png) are small, muted, and wrap across several lines. Shortcut hints in [07-main-menu.png](/home/frank/.cache/review-loop/read-r1/copy/07-main-menu.png) and [08-right-click-menu.png](/home/frank/.cache/review-loop/read-r1/copy/08-right-click-menu.png) are also much lighter than the menu labels. The menu labels themselves remain readable.

5. **Icons are compact, but none stands out as a serious recognition failure.** The toolbar and layer visibility icons are generally around 14–16 px, with some thin strokes. At a glance, the smaller eye, grid/snap, and collection controls may take an extra moment to identify. In [06-pen-tool-settings.png](/home/frank/.cache/review-loop/read-r1/copy/06-pen-tool-settings.png), the small pen-settings controls are still recognizable. I don’t see a major icon problem comparable to the text issues.

## Sizes and contrast

Approximate sizes from the screenshots: ordinary interface text is **12–13 px**; captions, helper text, and section headings are **10–11 px**; the shortcuts dialog title is about **24 px**. The headings are darker and bold, but small and widely letter-spaced.

The main interface text is much stronger: sampled dark text is about **5.8–6.2:1** against near-white backgrounds. Some secondary text is around **3.5:1**, while the palest counts and values appear near **2.6:1**. The exact values vary by element; these are estimates from the screenshot pixels. Text edges look clean at 1×. I don’t see a rendering or anti-aliasing problem driving the complaint.

## Keep

The main labels and values have good dark contrast. Selected items and active tools use a clear blue highlight, and bold section labels provide useful landmarks. The text on the canvas and the cut-out card’s main prompts are easy to read. The biggest opportunity is making secondary text easier to see and giving ordinary interface text more physical size on the high-density screen.