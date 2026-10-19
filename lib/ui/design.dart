import 'package:flutter/painting.dart';

/// Every colour, size and timing the interface uses, by role. Nothing in the
/// app types a value of its own: if a role is missing, add it here. Decisions
/// about taste (wording, motion, icon style) are in `docs/DESIGN.md`.

// ---- colour ----------------------------------------------------------------

/// Main text and the darkest marks drawn over the page.
const Color kInk = Color(0xFF222733);

/// Labels, hints and secondary text.
const Color kInkSoft = Color(0xFF5B6272);

/// Captions, counts, shortcuts and quiet icons.
const Color kInkFaint = Color(0xFF8A90A0);

/// Anything that cannot be used right now.
const Color kInkDisabled = Color(0xFFB4B8C2);

/// Icons on buttons.
const Color kIconInk = Color(0xFF444B5A);

/// Dividers and the edges of panels.
const Color kBorder = Color(0xFFD9DCE3);

/// The edges of fields, buttons and groups of buttons.
const Color kControlBorder = Color(0xFFD0D4DD);

/// Outlines that must show against white or grey: swatches, keycaps, grips.
const Color kOutline = Color(0xFFC3C8D3);

/// The side panels.
const Color kPanel = Color(0xFFF7F8FA);

/// The backdrop around the page.
const Color kWorkspace = Color(0xFFE4E6EB);

/// Selection, focus and the one thing that is on.
const Color kAccent = Color(0xFF2F6BFF);

/// A selected row, a hovered accented control.
const Color kAccentSoft = Color(0xFFE8EEFF);

/// Deleting, errors.
const Color kDanger = Color(0xFFC62828);

/// The dashed line of a cut in progress.
const Color kCutLine = Color(0xFFFF6D00);
const Color kCutFill = Color(0x22FF6D00);

/// Tooltips and the message at the bottom.
const Color kOverlay = Color(0xE6222733);

/// Lines and hover on accent-coloured surfaces (the name tag).
const Color kOnAccentLine = Color(0x55FFFFFF);
const Color kOnAccentHover = Color(0x33FFFFFF);

/// The see-through middle of a ring drawn over the page.
const Color kWash = Color(0x22FFFFFF);

/// Shadows: floating surfaces (menus, cards, pills), the page and handles,
/// and the faintest edge.
const Color kShadow = Color(0x44000000);
const Color kShadowSoft = Color(0x33000000);
const Color kShadowFaint = Color(0x1F000000);

// ---- spacing --------------------------------------------------------------

/// Gaps and padding, on a 4 px grid. 2 is only for the tightest nudges.
const double kSpace2 = 2;
const double kSpace4 = 4;
const double kSpace8 = 8;
const double kSpace12 = 12;
const double kSpace16 = 16;
const double kSpace20 = 20;
const double kSpace24 = 24;

// ---- panels ---------------------------------------------------------------

/// The height of every field, dropdown, button and button group.
const double kControlHeight = 28;

/// The side panels' margins, the gap between rows and between sections.
const double kPanelPad = kSpace16;
const double kRowGap = kSpace8;
const double kSectionGap = kSpace16;

/// A colour swatch: 11 of them, 4 apart, fit across the panel with room.
const double kSwatch = 18;

/// The column of row labels (Name, Layer, Opacity…).
const double kLabelWidth = 64;

// ---- type ------------------------------------------------------------------

/// Section labels, captions, counts, shortcut keys, the name tag.
const double kTextCaption = 11;

/// Labels, fields, menus, list rows, tooltips.
const double kTextBody = 12.5;

/// The app name, card titles, the empty-page hint.
const double kTextTitle = 14.5;

/// The interface font (bundled), and its three weights: ordinary text,
/// emphasis (names, buttons) and headings (section labels, titles).
const String kUiFont = 'Inter';
const FontWeight kWeightRegular = FontWeight.w400;
const FontWeight kWeightStrong = FontWeight.w600;
const FontWeight kWeightHeading = FontWeight.w700;

// ---- icons -----------------------------------------------------------------

const double kIconSmall = 13;
const double kIcon = 16;
const double kIconLarge = 18;

// ---- corners ---------------------------------------------------------------

/// Fields, buttons, tags, tooltips.
const double kRadius = 6;

/// Menus, cards, pop-overs.
const double kRadiusLarge = 10;

/// Fully round ends.
const double kRadiusPill = 100;

// ---- timing ----------------------------------------------------------------

/// How long the pointer rests before a tooltip shows.
const Duration kTooltipWait = Duration(milliseconds: 500);

/// Short transitions: a pop-over opening, a value easing in.
const Duration kQuick = Duration(milliseconds: 120);

/// Scrolling something into view.
const Duration kScroll = Duration(milliseconds: 220);

/// A new row's glow, so it is noticed.
const Duration kFlash = Duration(milliseconds: 1400);
