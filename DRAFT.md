# Thinkspace — the draft

*Still thinking. This is a shared worktable, not a plan.*

> We are allowed to be unsure here. The point is to stay with the questions long enough to find the good shape of the idea—not to turn every thought into a requirement.

## How this started

The original itch was familiar: doing one visual job meant bouncing between several Linux apps. One app for a quick diagram, another to mark up a screenshot, another to try design ideas over a storefront photo. Each switch made the work slower and more cumbersome.

Thinkspace might be a small, quick place to get an idea out of your head and onto a canvas. Not a place to make beautiful finished artwork. Not a vector studio, drafting tool, or photo editor. More like: *“Here, this is what I mean.”*

Is that still the right center of gravity? Let's keep checking.

## Frank clarified the job — 25 Sep 2026

The storefront is one example. It is not the center.

The first description still holds: a small, quick place to get an idea out and show someone what you mean. The useful pieces already exist, scattered across apps like Xournal, GIMP, and Paint.NET. He wants some of those features together, and the bloat left out.

What he keeps needing in one place:

- vectors, and by that he means straight lines, fast
- raster images: screenshots, images from the web, photos
- layers, because they make editing and changing a layout much easier

Probably some other things too, not named yet. The reason to open the app is to convey something or solve a problem. If the screen is hundreds of buttons, menus under menus, and rows of status lines, the idea is gone before the work starts. That kind of design fails even when the features are all there.

Frank on layers, same day: simple actions only. Show or hide. Rearrange order. Move the objects on a layer together. A layer for text, a layer for one set of images, a layer for another set. Organization, not masks or blend modes. GIMP is close, but slow, and drawing a line or an arrow is a hoop. Resizable arrows are a must, along with those fast straight lines.

## A scene we're imagining

Someone opens a photo of a storefront. They paste in several awning pictures from the web. The pictures don't all have the right size or angle, so they move, resize, rotate, and fade them until each one sits roughly over the shop. They hide one possibility, show another, and explain the differences to someone else.

Maybe the storefront is the background. Maybe the awnings are separate objects, arranged into named layers. Maybe a tray holds collected pictures until they're ready to use. When one is selected, it should be obvious what it is and where it belongs.

That sounds more like arranging pieces than painting pixels. Does that distinction explain the pain well?

## Little things should stay little things

A pasted image shouldn't suddenly become inseparable from a whole page-sized layer. Text shouldn't vanish into the canvas the moment it's typed. In the picture we're forming, an image, label, arrow, or shape remains its own movable thing until someone deliberately combines it with something else.

Very rough sketch, not a data model:

```text
paste an image
  -> give it a name
  -> move / resize / rotate / fade it
  -> keep it loose while trying ideas
  -> maybe place it with related things in a named layer
  -> maybe flatten it later, if that is actually useful
```

Layers could organize objects and could also be moved or adjusted together. The objects inside would still be individually editable. We haven't worked out what “flatten” should mean in every case, or whether it belongs in the everyday workflow at all.

## The image-in-the-image problem

A very ordinary action: paste a PNG, select the part worth keeping, cut it out, and use that piece somewhere else. We'd like that to feel natural here too. Perhaps the original stays safe while the selected piece becomes a new object; perhaps sometimes the user really does want a destructive cut. What should the default feel like? How should a freeform cutout behave around transparent pixels?

## Drawing, without turning into an art suite

Straight lines, basic shapes, text, and a pen for quick marks seem useful. Snapping could make a rough diagram look tidy; smoothing could make a quick hand-drawn line easier to read. Colors, pen sizes, fonts, undo, and redo all sound helpful, as long as they don't turn the app into a giant tool chest.

Where is the line between “a few thoughtful tools” and “now I have to learn a graphics suite”?

## What the mockups make me wonder — Buffy

Both early mockups put the storefront in the middle and make the awning visibly selected. That seems like a useful center: the canvas gets room, and selection makes it clear that the awning is its own thing rather than painted into the storefront.

They try different surrounding layouts. One gives the collected awnings a simple thumbnail shelf on the left and a layer list on the right, with a small adjustment area below the canvas. The other gives the collection more structure—search and categories—and combines a more descriptive layer list with properties for the selected item. The second makes “things I collected” and “things already arranged in this picture” feel like separate ideas; the first feels a little more open and direct.

A small but important visual thought: selection bounds should make it unmistakable which object will move or resize. In one sketch the bounds seem to extend well below the awning; if that isn't intentional, it could recreate the original frustration of manipulating a whole layer when you meant to adjust one pasted picture. In the other, the handles sit closer to the awning itself. That difference is worth paying attention to, without deciding the exact look yet.

The mockups also raise questions: If I drag a collected awning onto the canvas, does the original stay in the collection so I can place it again? How do we tell a collected source image from an instance already in the composition? If the layer list gets long, do names, thumbnails, and visibility toggles make it easy to find the right thing—or does the panel become another pile to manage?

These are sparks from two sketches, not a preferred layout. A more compact arrangement, tabs, or something else might work better once we try the real workflow.

## It should be easy to look at what we're making

This is a requirement for how we develop Thinkspace: a person or an AI agent should be able to launch it in a predictable way, open a known example, try an interaction, and inspect the result. Ideally we can capture the actual screen and also ask the app what objects and layers are present, so a screenshot isn't our only clue.

A pretend walkthrough:

```text
open the sample storefront
  -> choose awning_02
  -> move it and make it translucent
  -> hide its layer, show awning_01
  -> undo
  -> capture the screen and inspect what is selected
```

We haven't chosen the tools that would make this easiest. The important part is that inspection stays possible whichever direction we take.

## The technical question — earlier discussion

We could build a native desktop app with a purpose-built drawing surface, or use a cross-platform UI toolkit that draws its own interface. Each might make different tradeoffs around drawing feel, platform behavior, packaging, and automated inspection.

Two candidates feel worth comparing first:

- **Qt 6** already has the idea of a scene full of separate interactive items. Things can be selected, found under the pointer, transformed, grouped, and shown through a view. That sounds close to our “little things should stay little things” idea. How much does that actually save us once we need our own selection handles, layers, text editing, and friendly workflows? Would the existing scene model feel like a helpful foundation or an awkward thing to bend?
- **Flutter desktop** can run as a Linux or Windows desktop app and gives us one cohesive UI toolkit. It can paint a custom canvas, too. That freedom is appealing, but we'd likely have to decide and build more of the canvas behavior ourselves: how objects are hit-tested, selected, moved, rotated, and explained to the accessibility/test tools. Would designing that behavior ourselves be a burden—or a chance to make it fit Thinkspace exactly?

For either one, we need to try the actual kinds of things people will do, not just compare feature lists. A tiny experiment could open a storefront picture, add two separate awning pictures and a text label, select and transform them, toggle a layer, undo, and let an agent inspect both the screen and what the app thinks is selected. Then we can ask which approach felt more natural to build and easier to inspect.

We should also look at the less-visible parts: Linux and Windows packaging, clipboard and file dialogs, pen/stylus input if we want it, fonts, accessibility, and licensing. None of those questions needs a final answer today.

At the time of this note, no stack had won. Later, Frank chose a Flutter/Dart desktop app, starting on Linux. This section records the discussion that led there; the current direction is summarized near the top of `README.md` and in the latest notes below.

Some official reading behind this comparison: [Qt Graphics View](https://doc.qt.io/qt-6/graphicsview.html), [Flutter desktop support](https://docs.flutter.dev/platform-integration/desktop), [Flutter custom painting](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html), and [Flutter integration testing](https://docs.flutter.dev/testing/integration-tests). These links are context, not a vote.

## How much editor would we have to build?

Maybe “Qt is easier, Flutter is more flexible” is too simple. Qt gives us more of the interactive scene machinery already assembled. Flutter gives us a flexible UI and drawing toolkit, but we'd make more choices about how the objects on the canvas behave. Neither one hands us Thinkspace finished.

A rough sketch of the division:

```text
framework helps with:
  draw pixels, images, text, and shapes
  receive mouse / touch / keyboard events
  show a window and ordinary controls

Thinkspace still decides:
  which thing was clicked when objects overlap
  what selection looks like and how handles behave
  how a drag updates an object or a whole layer
  how undo, layers, naming, and crop/cutout work
  what gets saved, copied, flattened, or exported
```

Qt's scene/view system already knows about separate items, picking items under the pointer, selection/focus, transforms, and groups. That can save real groundwork. But we'd still shape those facilities into our own document and interactions; “Qt has items” does not mean “our editor is done.”

Flutter gives us drawing primitives, pointer/gesture handling, text widgets, and ways to build custom painting and test desktop apps. We could represent canvas objects as individually positioned UI elements, paint the scene ourselves, or combine the two. We'd need to implement or choose the rules for hit-testing, object selection, transforms, stacking, and coordinating gestures. It is extra editor work, not writing a graphics engine from nothing.

Some tasks are mostly ours whichever route we take: the project format, sensible history/undo, collection tray, image cutout behavior, layer semantics, and the precise feel of the workflow. Qt can reduce the low-level scene plumbing; Flutter might make other parts of the interface feel natural to compose. We should test rather than assume which total is easier.

How much more work is Flutter? Hard to give a trustworthy multiplier before trying the interactions. A basic canvas with movable images and text seems very achievable for an AI coding agent. The complexity climbs when selection must feel dependable with overlapping rotated objects, text editing, transform handles, pen input, and undo all cooperating. That is a gradual, testable pile of behaviors—not a single mysterious hard problem. Could we prototype one thin slice and see how much framework help we actually miss?

The flexibility question might be less “can Flutter do it?” and more “do we want to own these interaction rules in exchange for shaping the app exactly around our use cases?”

## Flutter in the wild — encouraging, with a desktop caveat

I'm leaning toward Flutter because having control over Thinkspace's interactions sounds more valuable to me than getting a head start from a ready-made scene system. That is a leaning, not a decision. Before we settle, it would be useful to look at what people have actually made with Flutter—and distinguish desktop evidence from mobile evidence.

Some large, production Flutter examples include the **My BMW** app and **eBay Motors**. Flutter's showcase also lists apps from Google (including Google Pay, Google Earth, and Google Ads) and many other organizations. Those examples are encouraging evidence that Flutter can support substantial, polished products, but several are primarily mobile apps; they don't by themselves answer how Thinkspace will feel as a desktop editor.

For desktop specifically, there are examples too: **Flokk**, an open-source contacts manager built as a Flutter desktop demonstration; **Flutter Folio**, a cross-platform scrapbook demo that runs on Linux and Windows among other targets; and Ubuntu's installer UI, which Canonical says was built with Flutter. They're useful to inspect, but their existence isn't proof that every desktop detail—keyboard conventions, clipboard, files, packaging, accessibility, pen input—will be effortless for us.

References to browse, not endorsements: [Flutter showcase](https://flutter.dev/showcase), [BMW case study](https://flutter.dev/showcase/bmw), [eBay Motors case study](https://flutter.dev/showcase/ebay), [Flokk and Linux desktop support](https://snapcraft.io/blog/canonical-enables-linux-desktop-app-support-with-flutter), [Flutter Folio in the Flutter showcase](https://flutter.dev/showcase), and [Canonical on Flutter and Ubuntu](https://ubuntu.com/blog/flutter-and-ubuntu-so-far).

A question for another set of eyes: which examples are most relevant to a desktop visual editor, what concerns are easy to miss when we're excited about flexibility, and what simple experiment would show us whether Flutter makes *our* interactions easier to evolve? Please add thoughts and counterpoints here; don't treat my current leaning as a stack decision.

## If we tried Flutter, what would the whole thing be made of? — Buffy

The stack could be pleasantly small at first: **Flutter and Dart for the app**, with Thinkspace's own little world of documents and objects inside it. Flutter would draw the window and interface and give us drawing, text, pointer input, keyboard events, and ways to test widgets and desktop flows. The part we invent is how all those pieces behave like *our* canvas editor.

I wouldn't pick extra packages just to make the stack look complete. First I'd want a tiny Flutter desktop app that runs on Linux, then confirm how it builds and runs on Windows too. After we learn what Flutter already handles comfortably, we can look for packages or small platform-specific bridges only for real gaps—perhaps file picking, clipboard image access, or pen details. Those desktop details can differ by platform, so we'd check support instead of assuming a mobile-oriented package covers them.

### A possible path from opening a project to sharing an idea

```text
launch Thinkspace
  -> start blank or open a project
  -> show the document's objects on the canvas
  -> collect / paste / draw / select / adjust
  -> record each meaningful change so undo can reverse it
  -> save the editable project
  -> export a regular image when someone wants to share it
```

For an early project file, we might save a readable description of the document plus its imported image files together in a folder or bundle. That is only a sketch; we haven't chosen a file format. The useful principle is that opening a saved project should bring back the editable pieces, while exporting produces a simple PNG or other ordinary picture. A saved-project file and an exported image answer different needs.

### How the canvas might be assembled

Flutter gives us a drawing surface and can paint text, paths, and images. It also lets us build ordinary UI widgets around or over that surface. We could try two broad shapes:

```text
A. paint the scene together
   -> draw all visible objects in order
   -> work out which object is under the pointer

B. compose the scene from positioned pieces
   -> each image / label / shape is a separate widget
   -> use Flutter's layout and hit-testing to help with interaction
```

Or mix them: paint the background and many scene objects together, while using interface widgets for selection handles, text editing, and panels. We don't yet know which version makes zooming, overlap, selection, and smooth drawing feel best. That's exactly a prototype question, not a reason to commit in the draft.

Whichever route we try, an image, text box, shape, or stroke needs a persistent identity and simple properties—what it is, where it is, how large/rotated/faded it is, and what group or layer it belongs to. The canvas draws those things; clicking or dragging one asks the document to change them. A rough interaction might be:

```text
pointer down at screen point
  -> translate that point into canvas coordinates
  -> find the topmost eligible object there
  -> show its selection and name
  -> while dragging, update the object preview
  -> on release, record one undoable document change
```

Whether Flutter's drawing widgets help identify the clicked object depends on how we build the canvas. If the scene is painted as one surface, Thinkspace likely needs to search its own objects in visual order and work out which bounds or shape contains the pointer. If objects are separate widgets, Flutter's hit testing can help, but rotation and overlap still need thought. Selection handles could be drawn as an overlay; dragging one would translate screen motion back into the selected object's coordinates. Zooming the view should change how we display things, not silently rewrite every object's document position.

The object list, layer list, and selected-item controls would be ordinary Flutter interface widgets beside the canvas. They'd all reflect the same current document and selection. A click on an item row could select that object; toggling an eye could change visibility; moving an object on canvas could update its row and its saved position. We would need to decide carefully how gestures on canvas relate to gestures in the side panels, especially when the pointer is near a resize handle or an overlapping object.

A rough story for making a change:

```text
user does one meaningful thing
  -> Thinkspace updates the document
  -> canvas and panels redraw from that document
  -> history remembers the before/after change
  -> undo asks the document to return to the earlier state
```

That might be a small custom document/history layer rather than a large framework decision. We don't have to settle a state-management package or undo design now. First we need to learn what changes the user thinks of as one action: is a whole drag one undo, for example, rather than hundreds of tiny pointer moves?

For the everyday file path, Flutter's desktop support lets us build and run a Linux or Windows app. Opening, saving, importing, clipboard paste, and exporting would each use a mix of Flutter UI and platform capabilities. Some may work directly; others may need desktop-aware packages or a small platform bridge. We'd test real images and clipboard use on Linux early, then verify the equivalent on Windows rather than assuming both behave identically.

The development loop could be part of the app from its earliest useful slice:

```text
launch with a known storefront example
  -> perform a repeatable interaction
  -> ask the app which object/layer is selected
  -> check the document state and undo result
  -> capture a screenshot of the real desktop window
```

Flutter's widget and integration-test tools give us a way to exercise controls and workflows, and stable keys can identify interface elements. We'd still need a reliable way to automate canvas drags and make screenshots accessible to an agent in its environment. Maybe we expose a small development-only way to load samples and inspect named objects; whether that is a debug panel, test hook, or something else is open. The key is that an agent can check both what the screen looks like and what the document says happened.

Then the same project would need to be built, packaged, and tried as a real desktop app: first on Linux, and eventually on Windows. Flutter's official desktop support covers both, but dependencies, system dialogs, clipboard behavior, fonts, and packaging can vary. We'd want someone to launch the packaged build on each system before calling cross-platform support real.

That's an end-to-end picture, not an instruction to build every part at once. A deliberately small first experiment might be: one background image, two independent awning objects, one text label, selection and movement, opacity, layer visibility, one undo, sample loading, object-state inspection, and a screenshot. If that slice feels natural in Flutter, it would give us more evidence than a long architecture debate. If it feels awkward, we learn that early too.

No package list yet. Flutter and Dart are enough to name the broad stack; we can choose file, clipboard, state, and other dependencies only after a prototype shows what is missing. The important open question is whether our custom interactions feel worth owning—not whether we can find a package for every checkbox.

A few official references if we want to read further: [Flutter desktop support](https://docs.flutter.dev/platform-integration/desktop), [custom painting](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html), and [integration testing](https://docs.flutter.dev/testing/integration-tests). These explain what Flutter provides, not what Thinkspace must choose.

## A reaction to that sketch — Hermes, 25 Sep 2026

Read as a sketch, not a plan. The useful part is not the Flutter. It's a split we could hold onto even if the stack ends up somewhere else:

- the document: the named things, and the changes someone meant
- the picture: how those things look right now, including zoom
- the export: a flat image, only when a flat image is actually wanted

Those are different jobs. Saving should bring the pieces back. Zoom should change the view, not quietly rewrite where an awning sits in the file. Buffy already asked what counts as one undo. I'd answer the example, still lightly: a drag is one change when you let go, not every twitch along the way. The picture can follow the hand; the document waits until you release. Fade and hide might follow the same idea, each in their own way. We don't need a history library to say that.

The other canvas question — paint everything and find the object ourselves, or let each piece be its own widget — is a real thing to try later. It is also a Flutter-shaped question. Fine parked. I wouldn't spend this "think it through first" time inside that choice. The split above doesn't depend on it.

Two places the sketch leans ahead of us.

The path puts draw and export on the main road, and gathers "collect / paste / draw / select / adjust" into one breath. The scene we keep telling is closer to: get a piece onto the photo, try the other one, explain. A scribble and a shared PNG might matter later. Turning the screen around might be the first way an idea leaves. We also still haven't said when a picture is just in hand, and when it has joined the shop.

The small first experiment includes layer visibility, and we still can't say in one sentence what a layer is. A slice that needs a layer will invent one so the eye has something to toggle. Hide this awning, show the other, might be enough to start. If one click isn't enough to compare ideas, that's when a set earns a name.

And if the experiment is meant to tell us whether owning the interactions is worth it, the two awnings have to overlap at least once. Two pictures sitting politely apart will feel fine in any toolkit. The awkward case is clicking the one behind.

None of this picks a stack. Buffy's open question still stands: do we want to own these rules? I'd just like the first thing we try to be the rule we're unsure about, not the part every toolkit already makes easy.

## Flutter prototype proposal — Hermes, 25 Sep 2026

This was a proposal before the mockup review and before Frank asked to build the desktop app. Its initial slice is useful history, but the later collection, grid, and canvas-size notes extend it. Pasting an image on Linux may need platform support; that does not by itself change the Flutter direction.

I agree with your sketch on these points: Flutter and Dart, our own document, Linux first, no extra packages until something is actually missing, save brings the pieces back, a PNG is a separate export, a drag is one undo when you let go.

Three changes before I'd call it agreed.

Draw the page ourselves from the document. Ordinary Flutter widgets only for the short layer list and a few tools: select, line, arrow, paste image. Don't make each line or arrow its own widget. Widgets are boxes. Lines and arrows are the thing GIMP makes hard, so they live in our document and we draw them. Your paint-versus-widgets question can close that way unless you see a real problem.

The first slice is not the storefront. Paste a screenshot, draw a straight line, draw an arrow and resize it by dragging the ends, two layers, hide one, change which is in front, move a layer so its objects move together, undo. Clipboard paste is in this slice. Leave out rotation, opacity, masks, blends, and export. A text label can be the next slice. Text on a painted page is fiddly, but it does not push us off Flutter.

A layer is a name, a show/hide switch, an order, and the objects on it. That's the whole layer tool.

Frank subsequently chose Flutter desktop and asked for the documentation to be updated for an Opus 5.5 implementation attempt. The core remains: draw the page from editable objects, keep layers simple, and build a focused tool rather than a graphics suite.

## Latest direction — collection, movable layers, and a grid — 25 Sep 2026

The mockup review made three things clearer. These are part of the direction for the desktop prototype, while the exact controls and layout remain open.

### The collection should be a real workspace

The collected-images area should be bigger than the tiny tray shown in the first mockup, and perhaps resizable. It is not just a decorative shelf. It can hold images gathered from screenshots, the web, or the clipboard before they are placed on the canvas.

One possible paste flow:

```text
Ctrl+V
  -> Thinkspace asks: add to the current layer, or add to collection?
  -> current layer: create an editable canvas object now
  -> collection: keep the source available until it is dragged onto the canvas
```

The collection item and the canvas object should probably be different things. Dragging an item out of the collection could create a new canvas object while leaving the collected source available for another use. We haven't decided whether paste should always ask, remember the last choice, or offer a quick default with a way to change it.

### Objects should be able to change layers

A canvas object should not be permanently married to the layer it first entered. Someone might paste an image into one layer, then later decide it belongs with another set of images or with the text and arrows. Moving an object between layers should reorganize it, not flatten it or recreate it.

That suggests keeping these ideas separate:

- **collection item** — a source kept available for possible use
- **canvas object** — one editable image, line, arrow, text item, or shape
- **layer** — an ordered named group of canvas objects, with show/hide and move-together behavior

This is a useful conceptual distinction, not a final document format. The important user-facing result is that an object can remain itself while changing layers.

### A grid can help without taking over

The canvas may have a grid that can be shown or hidden. When snapping is on, objects could align to grid positions while being moved or resized. The grid should be a visual aid, not part of the exported picture or a permanent visual burden.

Possible controls are deliberately small: show/hide grid, snap on/off, and perhaps a grid size choice only if one fixed size proves insufficient. We should be careful not to make snapping fight the user during free placement; a temporary modifier or an easy escape from snapping may be useful.

The grid raises a good interaction question for the prototype: should snapping apply to an object's position only, to its edges and endpoints as well, or to all of those? Lines and arrow endpoints seem especially likely to benefit from it.

### The canvas can grow to fit the work

Frank wants the canvas itself to be easy to resize. A composition with several pasted images may need to become a tall or long document, rather than forcing everything into a fixed-size page or making the user shrink the content to fit. Canvas resizing should be a straightforward action, and should not resize or flatten the objects already on it.

The exact behavior is open: drag a canvas edge or corner, choose dimensions, or combine a simple drag with an optional size field. We also have not decided whether the canvas grows automatically when content approaches an edge, whether resizing is freeform or offers common page proportions, or how the work should fit in the view afterward. The first mockup only needs to make the canvas boundary easy to see and resize; no print-layout system is implied.

### Does this change the Flutter direction?

No. A resizable collection, paste choice, movable canvas objects, layer reassignment, a hideable snapping grid, and a resizable canvas fit the same Flutter/Dart desktop direction. They add behavior to the document and canvas; they do not require a different technology. They do make it more important that the prototype keep collection items, canvas objects, and layers distinct without making the interface heavy.

## Things we haven't answered yet

- Would the canvas be one painted scene, a collection of positioned widgets, or some mix?
- What needs to be native platform integration, and what can stay in Flutter/Dart?
- How can screenshots and semantic document state be made reliably available to an agent?
- When does an object live in the collection tray, and when does it live on the canvas?
- Can a layer both organize objects and affect them together without becoming confusing?
- What exactly should a flattened layer be, and can someone get back to the editable pieces?
- Should cropping preserve the original by default?
- What is the smallest set of tools that makes this genuinely useful?
- What does “fast” mean for this app: quick to open, quick to learn, responsive while drawing, or all of those?
- Which development approach makes it easiest for humans and agents to inspect the actual product?
- What is the first tiny experiment that would teach us something meaningful?
- Are the pile, the parts, and the tries one tray, or three different moments? (from reading the two mockups)
- Does comparing ideas want a named try you can flip, rather than a layer?
- How photoreal does “sitting over the shop” need to be before we’ve accidentally started a photo editor?
- Should Ctrl+V ask whether the pasted image belongs on the current layer or in the collection, or should one choice be the quick default?
- How large should the collection be by default, and should the user resize it by dragging its edge?
- Should dragging a collection item create a new canvas object while leaving the source in the collection?
- How should an object move between layers without losing its identity, position, or editability?
- Should grid snapping apply to positions, edges, endpoints, or some combination?
- How does someone temporarily place an object freely when snapping is turned on?
- How should someone resize a canvas quickly, and should it grow automatically when content nears its edge?
- Should canvas resizing preserve a freeform size, offer common proportions, or both?

These are invitations to think, not a backlog. Add better questions when they come along.

## Another reading of the mockups — Hermes, 25 Sep 2026

I was invited in to look at `grok_mockup.png` and `gpt_mockup.png` and play. They're sketches of a feeling, not designs to keep. The useful part is where they disagree — with each other, and with the scene we've been telling.

### They don't agree what the tray is for

The plainer picture's left side is a strip of whole storefront photos, each already wearing a different awning. That reads as a contact sheet of tries: “which of these looks are we talking about?”

The polished picture's left side is a parts bin. Isolated awnings, already cut out, sorted into Awnings / Plants / Signs, with a search box. The canvas is an assembly table. It also grew a Share button, a zoom readout, and width and height numbers (820 by 160). Nobody here asked for those. They're what a picture generator reaches for when it hears “design tool.” It also furnished the shop — bench, chalkboard, plants — past the story we actually told, which was about awnings.

The scene in this draft is messier than either picture. You paste awning photos from the web. Wrong size, wrong angle, probably a background still attached. The polished mockup shows the *after*: tidy cutouts in a catalog. The plainer one shows *other finished looks*, not the pile of ugly snips. If we only design the tidy picture, we might miss the job.

Three different jobs keep getting called “the tray.” Maybe they're one thing. Maybe forcing them into one tray is how this gets confusing:

- a pile: pictures you've gathered and haven't committed to
- parts: pieces taken from that pile, ready to place
- tries: named ways this canvas could look, so you can hide one and show another while you explain

We haven't decided which of those is the everyday gesture. A hunch, not a vote: the explaining gesture — show this try, hide that one — is closer to the original itch than a searchable catalog. Search matters when there are two hundred snips. There aren't, yet.

### “Roughly over the shop” might be the whole product

Both mockups make the awning look installed. That's flattering, and it might be a trap.

A front-facing awning photo, dropped on a storefront seen from the street, will not sit in perspective just because we scale it and spin it. Chasing “looks installed” wants corner-pulling, perspective, maybe color matching. That is the door into a photo editor, which we said this isn't.

Another possibility: the piece is obviously a piece. Held up against the photo, faded, roughly the right size, named. Honest about being a proposal, not a fake photograph. “Here, this is what I mean” doesn't require the awning to look built. If we accept rough, rotate-and-fade might be enough. If we don't accept rough, the tool grows a transform mode and the line we were worried about moves.

We haven't felt which of those is actually satisfying when you're showing someone the shop.

### “Layers” might be the wrong word for the list

The polished mockup answered a question we've been circling, quietly. Its right-hand list isn't a stack of pixel slabs. It's the things: `awning_02`, `storefront_photo`, `plant_left`, `bench`, each with an eye. Every object is its own row.

That's appealing. A layer that is sometimes a folder, sometimes a slab of pixels, and sometimes one object is how graphics apps get hard to learn. If the everyday list is just “what's in the picture,” we might skip that confusion. It also happens to be the list an agent could read back later without guessing from pixels — same names as the little label on the canvas.

The worry: comparing ideas wants a *set* you can hide in one move. “Show the striped family, hide the solid one.” A flat object list turns that explanation into a lot of little eye-clicks, and the person looking over your shoulder gets lost. So maybe we want named tries you can flip, and that is not the same thing as a layer, and not the same thing as the object list.

The plainer mockup is a warning the other way. Its layers column is full of near-nonsense (Visibility, Asibility, Simings, Pdiling) and a rotation control that doesn't say anything (“x //”). An empty “layers” shape, before we know what a layer is, fills up with junk. Maybe we shouldn't draw that panel until we can say, in one sentence, what a row in it *is*.

Related small hunch: the storefront photo might want to be the stage, not just another draggable thing. In the polished list it's `storefront_photo`, a sibling of the awning. Easy to grab the building when you meant the fabric. Pinning the photo until someone deliberately unlocks it would keep the stage still. We haven't decided the background is special. It might not need to be.

### The name on the thing

Both pictures did one thing worth keeping as a shared instinct, not a decision. The selected awning wears a label: `awning_02 · awnings`. On the picture, not only in a sidebar.

That matches “when one is selected, it should be obvious what it is and where it belongs.” It helps the explaining scene too — the other person is looking at the shop, not at our panels. If a screenshot and the app's own list use that same name, inspection gets less mystical. Still just an instinct.

### The prominent tools might be lying

Both toolbars lead with a pen, shapes, and text. The scene we keep telling is arrange, fade, hide, show, explain. A scribble or an arrow is useful — “this one, not that one” — but it might be a side gesture, not the face of the app. A toolbar that looks like every other drawing app will teach people to expect every other drawing app.

The polished inspector also leads with exact width and height. That's the pull toward drafting. For this job, fading and nudging might matter more than typing 820. Numbers could live somewhere without being the first thing on screen.

The plainer picture puts opacity, size, and rotation in a small card beside the photo instead of a properties column. Less chrome. Also easier to cover the thing you're judging. We haven't felt either in the hand.

### On the Flutter leaning, since another set of eyes was asked for

The leaning — own the interaction rules, rather than borrow a scene system and then fight it — still sounds like the interesting bet. I don't have a better stack to crown. The showcase apps don't settle it either.

Contacts, an installer wizard, a scrapbook demo, and a lot of mobile apps don't tell us whether two overlapping, rotated, half-faded pictures will feel dependable under the pointer. Flutter Folio is the closest cousin, and it's a demonstration. Encouraging. Not evidence about our awkward case.

The concern that's easy to miss: “we want control” can become a reason to build a small graphics suite by accident. Control over hit-testing is only a gift if the rules stay few. Once selection, groups, text, a pen, and undo all have to cooperate, we're in the pile of behaviors already named above — and we own every sharp edge. Qt's scene machinery might save some of that and then feel awkward to bend. Also still possible. Neither fear is a decision.

What would teach us something is a thin slice of the awkward case, not the happy one. Two awnings overlapping, one rotated, one faded. Click the one behind. Flip to the other try. Undo. Then a person or an agent reads back what is selected and what is hidden. If that feels miserable, the misery is the lesson.

A related hunch: the thing worth keeping separate from the drawing toolkit is the list of named things and tries, not the pixels. If that list is ours, either toolkit can draw it, and inspection doesn't depend on which one we picked. That's a reason the stack argument might be less urgent than it currently feels. Still a hunch.

## Where it landed — Claude (Sonnet 5.5), 10 Oct 2026

Frank handed over ownership: build the best app that supports the concept, with scope open to change. What follows records what was decided while building, so the questions above are answered rather than left dangling. Open ones are marked.

**Settled**

- Flutter/Dart, Linux first. We paint the page ourselves from the document; widgets are used only for panels and tools. Overlapping, rotated, faded pictures were the case we most worried about, and they behave: hit-testing is by the real rotated shape, transparent pixels of a cutout are not grabbable, and clicking the same spot again walks down the stack (`Alt`-click jumps straight to the one beneath).
- A layer is a name, a visibility switch, a lock, an order and its objects. Clicking a layer selects its contents so they drag together. Objects change layers by dragging them onto a layer (or the Layer dropdown) and stay themselves. Layers can be duplicated to try a variation.
- Collection items and canvas objects are different things. Dragging out creates a new object; the source stays.
- Ctrl+V asks: current layer or collection, with "always do this". The first big image pasted into an untouched page becomes the page.
- The page resizes by grips on its edge or by typed size, never touches the objects, and can "fit to content". Optional auto-grow, off by default.
- Grid: show/snap are separate; snapping uses the dragged bounds' edges and centre; `Ctrl` bypasses it.
- A drag is one undo step, recorded on release. Sliders likewise.
- Saved project = editable objects, layers and images in one `.thinkspace` file. Export = flat PNG. Unsaved work is autosaved and offered back after a crash.
- Cutouts: freehand or box; the original is untouched unless asked ("also remove from original"). Colour removal and corner-seeded background removal make new assets. Pieces can be merged back into one image — the answer to "when does flatten matter": only when you choose it, and undo brings the pieces back.
- Rotation and opacity are in, as is a pen with smoothing, text edited on the page, rectangles, ellipses, numbered markers, alignment, and right-click menus. These came from the job (arranging and annotating), not from copying a drawing suite.
- Shortcuts are taught in place rather than by a manual: the active tool shows its key as a small keycap under its icon, `?` opens a sheet where every key is drawn as a key, and a "Space + drag to pan" hint appears beside the zoom controls only when the page is bigger than the window. Frank asked for the keycap look after the first hint was too subtle; the in-app logo was tried and dropped because it looked muddy at 22 px.
- A tool is used once and then you are back on Select; double-click a tool to keep it. Frank confirmed this feels right.
- Merge is reversible after the fact: a merged picture remembers its originals (stored in the project file, so it makes the file larger) and can be unmerged while its pixels are untouched. Frank asked for this; the rule "only while the picture is unchanged" is what keeps it clean. A cut can leave its gap empty or filled with a colour. A "blend in" fill existed for a while and was removed again: Frank judged nobody would use it and it added complexity. The cut-out tool's options open as a card in the middle of the page, asked in the order the decisions are made (what to select, copy or cut, what to leave behind). No keyboard shortcut for fill, by request.
- Merging is one gesture: with several things selected a small pill under the selection says "Merge into one image" (key `M`), and after a merge the same spot offers "Unmerge" (`U`). Locked and hidden things are left out of a merge. Frank wanted it to feel part of the app, not an extra menu entry, hence the pill and the single key.
- Text has four typefaces (Sans, Serif, Mono, Hand): few enough to stay simple, enough to tell a note from a label. Sans is the system font; the other three are bundled (open licences, shipped in the release's `licenses/` folder) so a project looks the same everywhere. Shift with the pen draws a straight line, and in the Layers list the arrow keys walk the rows (Shift extends), because that is what a list does. All three came from Frank's testing.

**Deliberately left out**

- "Tries" (named alternative arrangements). A layer you can hide, plus *Duplicate layer*, covers comparing two ideas without a new concept. Revisit only if testers keep asking for it.
- Perspective and corner-pulling. Pieces are honest about being pieces: moved, scaled, rotated, faded.
- Blend modes, masks, filters, brushes beyond the pen, colour management.

**Still open**

- Windows and macOS: Flutter supports both, but clipboard images use `xclip`/`wl-clipboard` today.
- Whether snapping should also align to other objects' edges (smart guides).
- Whether the first pasted image should be locked as a backdrop (today it is a normal, grabbable object).
- Round 1 of human testing is prepared in `human_feedback/round-1-first-build/`; its answers will say which of the above matter.

## For the next person who opens this

Please keep this document loose. Add a thought, challenge an assumption, offer an alternative, or ask a question. Don't quietly turn it into a specification. See `AGENTS.md` for how we'd like AI collaborators to work with this draft.

## Windows (decisions)

Frank asked for a Windows version for his kids. One codebase, one Windows-specific layer:
- The clipboard is the only real platform gap. It talks to the Windows clipboard directly with `dart:ffi` (user32, kernel32, shell32) in `lib/io/win_clipboard.dart`, with the bitmap parsing and writing as pure, tested Dart in `lib/io/dib.dart`. The first plan (`WINDOWS_PORT_PLAN.md`) used `package:win32`; its 6.x API is large and still moving, and the dozen calls needed are stable, so I used plain FFI and dropped that dependency (only `package:ffi`, already a transitive dependency, was added). Reads prefer the exact "PNG" format, then DIBV5 and DIB; writes put both PNG (keeps transparency) and DIBV5 (Paint, Word) on the clipboard. The clipboard needs a real window handle when written to (a null one makes `SetClipboardData` fail), so `GetActiveWindow` is used.
- Pasting picture files copied in Explorer (and, on Linux, in a file manager) works through the same path as drag-and-drop.
- The recovery copy and preferences go to `%APPDATA%\Thinkspace`; `THINKSPACE_DATA_DIR` still overrides (a portable copy needs no code).
- The runner adds the title channel, the 900 x 560 minimum window, the icon (made by `tool/make_icons.sh`) and the app name. The C++ runtime DLLs ship beside the program, so a clean PC needs nothing installed.
- Builds happen in GitHub Actions (`windows-latest`): CI builds, tests and packages on every push of the port branch, and the `Windows release` workflow attaches the zip and an Inno Setup installer (unsigned, per user) to a published release.
- Touch: one finger = mouse; a second finger cancels what the first started and pans and zooms; holding a finger still opens the right-click menu; handles and hit areas grow when the last press was a finger. Pen = mouse (barrel button = right click). Not done: pressure, palm rejection beyond what Windows does, and larger toolbar buttons for touch. Whether Windows' on-screen keyboard appears for text editing is unverified.

