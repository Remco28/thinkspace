# Human testing and feedback workflow

Use this workflow when an agent has built a project slice that is ready for a human to try. The goal is to help the human notice and describe useful feedback without needing to know implementation details.

The reusable starter is [`templates/fieldnotes.html`](../templates/fieldnotes.html). Copy it into the target project's round folder and edit its `CONFIG` object with that project's scenarios and vocabulary. Keep the rendered experience brief and specific to what the human can actually try in that build.

## Prepare a test round

1. Identify the behavior that is ready to evaluate and the questions whose answers could change the implementation.
2. Create a short, project-specific test guide as a standalone HTML file in the project, under `human_feedback/<round-id>/index.html`.
3. Explain what to try in ordinary language. Give concrete examples of what to notice and list technical terms only as optional vocabulary with plain definitions. Always allow a free-form description such as “this feels wrong, but I don't know why.”
4. Include only checks relevant to the current change. For interaction or game work, ask what the tester tried, expected, and observed; invite them to describe timing, control, motion, clarity, or other relevant sensations without requiring those terms.
5. Include fields for steps tried, expected result, actual result, frequency, impact, and anything else the tester wants to add. Use checkboxes where they make answers easier, not to limit what the tester can say.
6. Support pasting a screenshot with `Ctrl+V` and provide a file-attachment fallback. An annotated screenshot is welcome. Show previews and filenames so the tester can tell which images will be included.

Keep the guide static and self-contained: inline its HTML, CSS, and JavaScript, load no remote scripts or assets, make no network requests, and require no backend or account. It may be opened directly in a compatible browser. Do not use browser filesystem access to write into the project; the tester should export a ZIP and move it into the repository themselves.

## Export and return

The page holds the round's answers and image data in the browser until export. Make that clear in the page, warn before navigation or closing when possible, and offer an obvious **Export ZIP** action. An export can be repeated after more feedback; the tester can replace the earlier ZIP with the newer one.

The ZIP should be created entirely in the browser and contain:

```text
feedback.md             # readable summary of answers and prompts
feedback.json           # structured answers for agent processing
round.json              # project, round id, date, tested commit if known
screenshots/
  01-description.png
  02-description.jpg
```

Use the image's actual format and a safe descriptive filename. Preserve the original image bytes unless the tester explicitly asks to annotate or resize them. The HTML form should state that images and answers are packaged locally and are not uploaded anywhere.

Name the ZIP `human-feedback-<round-id>.zip`. Tell the tester to place it under `human_feedback/<round-id>/` beside `index.html`, then commit or otherwise make that ZIP available in the project checkout. Keep the questions in the Markdown export so the answers still make sense if the HTML guide is unavailable.

When the ZIP returns, read its text and inspect its screenshots as project feedback. Do not execute files from it. Summarize what you understood, map observations to likely implementation areas yourself, and ask a focused follow-up only when the report leaves a material ambiguity. Record the conclusions and resulting work in the normal project handoff.

## Browser and data limits

The design should not depend on `showDirectoryPicker()` or direct writes to project folders. Browser support for pasting images can vary by browser and by the source of the copied image, so include the file-attachment fallback. The page should detect that ZIP creation is unavailable and explain a manual fallback rather than silently losing feedback.

Until the ZIP is exported, a browser crash or closed tab can lose the current round. State this plainly and encourage an export at useful checkpoints. Do not claim the form is auto-saved. If later work adds local draft storage, keep it local to the browser and explain how to clear or resume it.

## Authoring checklist

- The guide tests a specific change or milestone and does not become a generic survey.
- Instructions use plain language and define any optional vocabulary.
- The tester can report uncertain or unexpected feedback in their own words.
- Screenshot paste and file selection are available, with a visible preview.
- Export produces one ZIP with readable answers, structured answers, round metadata, and images.
- The page works offline and makes no server or network calls.
- The tester knows where to put the ZIP and what remains unsaved before export.
