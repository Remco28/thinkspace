# Known bugs

- **A long message runs into the zoom bar** (found 2026-11-07 by the review of the selection tag; there before it). Messages are centred at the bottom of the canvas area, and the zoom bar sits at the bottom left. When the canvas area is narrow or the message is long ("Nothing to merge: …", "Drop images (PNG, JPG, …)", the one-time Ctrl+L tip) the message box covers the zoom bar's right end. Moving all messages up clears it but puts them over the paste chooser (`bottom: 56`) and the page's lower edge; a fix needs to pick a spot that clears all three.
