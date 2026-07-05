# BBCode Formatting Package

The `bbcode` package provides a robust, extensible BBCode parser and formatter for rich text in console logs and terminal output. It translates BBCode tags into standard ANSI escape sequences, supports variables, and includes advanced conditional and length-based tag functions.

## Features

- **Text Styles**: Bold, italic, underline, and strikethrough.
- **Colors**: Predefined named colors and 24-bit hex colors for both foreground and background.
- **Dynamic Variables**: Context-sensitive substitutions for timestamp, log level, location, message, and thread ID.
- **Extensible Tag Functions**: Functional tags like `len` and `hour` that can be registered in a global dispatcher.
- **Nesting**: Fully supports nested tag functions (e.g., executing tag functions as arguments to other tag functions).
- **Conditional Evaluation**: Control output dynamically with condition expressions (e.g. comparing time or message length).

---

## API Reference

### `validate`
```odin
validate :: proc(text: string, allow_variables := false) -> (err_msg: string, ok: bool)
```
Validates the syntax of the input BBCode string. Checks for unclosed or mismatched tags, invalid color parameters, and syntax errors in conditional tags.

- `allow_variables`: If `false`, variable tags (`[time]`, `[message]`, etc.) will be flagged as syntax errors.

### `format`
```odin
format :: proc(text: string, enable_color := true, allocator := context.allocator) -> (result: string, err_msg: string, ok: bool)
```
Validates and parses the BBCode string, applying styling rules.
- If `enable_color` is `true`, tags are converted to ANSI terminal escape sequences.
- If `enable_color` is `false`, styling tags are stripped out, returning plain text.

### `strip`
```odin
strip :: proc(text: string, allocator := context.allocator) -> (result: string, err_msg: string, ok: bool)
```
A convenience wrapper around `format` with `enable_color = false` to remove all styling and return plain text.

### `process_colors`
```odin
process_colors :: proc(text: string, enable_color: bool, allocator := context.allocator) -> string
```
A lenient formatter that processes BBCode formatting but, if validation fails, gracefully falls back to returning the original string instead of returning an error. Used internally during log rendering.

---

## Supported Tags

### Standard Styles
| Tag | Description | Output Style |
| :--- | :--- | :--- |
| `[b]...[/b]` | Bold | **Bold** |
| `[i]...[/i]` | Italic | *Italic* |
| `[u]...[/u]` | Underline | <u>Underline</u> |
| `[s]...[/s]` | Strikethrough | ~~Strikethrough~~ |

### Color Tags
- **Foreground Color**: `[c=<color_name>]...[/c]` or `[c=#RRGGBB]...[/c]`
- **Background Color**: `[bg=<color_name>]...[/bg]` or `[bg=#RRGGBB]...[/bg]`

*Predefined Colors*: `black`, `red`, `green`, `yellow`, `blue`, `magenta` (or `purple`), `cyan`, `white`, `gray` (or `grey`, `dark_gray`), and bright variants (e.g., `bright_red`, `bright_blue`).

> **Note:** `[color=...]`/`[/color]` are **not** valid tags in the logging BBCode parser — they are only supported in the graphics text renderer (see [Graphics Text BBCode](#graphics-text-bbcode) below).

### Context Variables
When formatting templates during log emitting, the following tags retrieve current context fields:
- `[time]`: Current log timestamp.
- `[location]`: Code location of the log event.
- `[level]`: Log severity level.
- `[message]`: The log message content.
- `[thread_id]`: Thread ID processing the log.

---

## Advanced Tag Functions

Dynamic tag functions execute logic when parsed. They are registered in the global `TAG_FUNCS` registry within [logging/bbcode/advanced.odin](/logging/bbcode/advanced.odin#L24).

### `[len <content>]`
Returns the integer length of the evaluated inner content.
- Example: `[len [message]]` evaluates to the length of the log message.

### `[hour]`
Extracts and returns the hour component (as an integer) from the context's time string.
- Example: If `[time]` is `[2026-06-20 18:45:00]`, `[hour]` evaluates to `18`.
### `[if <condition>: <then-value>]` or `[if <condition>: <then-value> ? <else-value>]`
Evaluates a condition and returns `<then-value>` if true. If the condition is false, returns `<else-value>` (when using the `?` ternary else format) or an empty string.
- Supported operators: `<`, `>`, `<=`, `>=`, `==`, `!=`.
- The condition supports both integer numeric comparisons (such as `len(message) > 20`, `time < 20h`) and string variable comparisons (such as `level == debug` or `level == "info"`). If either operand cannot be parsed as an integer, the engine falls back to lexicographical string comparison.
- The condition, `<then-value>`, and `<else-value>` can all contain nested tag functions.

### `[upper <content>]`
Converts all text characters inside `<content>` to uppercase, safely preserving ANSI escape sequences (without capitalizing the escape control suffix `m`).
- Example: `[upper hello [b]world[/b]]` evaluates to `HELLO WORLD` (with `WORLD` styled in bold).

### `[lower <content>]`
Converts all text characters inside `<content>` to lowercase, safely preserving ANSI escape sequences.
- Example: `[lower HELLO]` evaluates to `hello`.

---

## Graphics Text BBCode

The `draw_text_bbcode_ttf` procedure in `src/graphics/text.odin` uses a **separate BBCode dialect** from the logging system. It renders styled text into the 2D batch using a TTF font and supports a superset of tags designed for real-time HUD/UI rendering. These tags produce GPU vertex colors — they do **not** emit ANSI escape sequences.

### Foreground Color
| Tag | Description |
| :--- | :--- |
| `[color=<name>]...[/color]` or `[c=<name>]...[/c]` | Named color (same predefined names as the logging system). |
| `[color=#RRGGBB]...[/color]` or `[c=#RRGGBB]...[/c]` | 24-bit hex foreground color. |

*Predefined color names*: `red`, `green`, `blue`, `yellow`, `orange`, `magenta`/`purple`, `cyan`, `white`, `black`, `gray`/`grey`.

### Foreground Opacity
| Tag | Description |
| :--- | :--- |
| `[opacity=<value>]...[/opacity]` | Sets the alpha of the text. Accepts a float `0.0`–`1.0` (e.g. `0.5`) or an integer `0`–`255`. Fully opaque at `1.0` / `255`. |

Opacity tags are **stackable**: the innermost value takes precedence. When `[/opacity]` is closed the previous opacity is restored.

```bbcode
Normal text [opacity=0.5]Half transparent[/opacity] back to normal.
[opacity=0.3]Dim [opacity=0.9]Almost opaque[/opacity] dim again[/opacity]
```

### Background Color
| Tag | Description |
| :--- | :--- |
| `[bg=<name>]...[/bg]` | Solid named-color background block drawn behind each glyph. |
| `[bg_color=<name>]...[/bg_color]` | Alias for `[bg=...]`. |
| `[bg=#RRGGBB]...[/bg]` | 24-bit hex background color. |

Background blocks are rendered as solid quads from the font's `descent` baseline to the `ascent` line for each character's advance width.

### Background Opacity
| Tag | Description |
| :--- | :--- |
| `[bg_opacity=<value>]...[/bg_opacity]` | Sets the alpha of the background block. Accepts a float `0.0`–`1.0` or an integer `0`–`255`. |

Background opacity is independent of foreground opacity and is also stackable.

```bbcode
[bg=blue]Solid Blue[/bg]
[bg=green][bg_opacity=0.4]Transparent Green Background[/bg_opacity][/bg]
[color=yellow][bg=red][bg_opacity=0.5]Yellow text on semi-transparent red[/bg_opacity][/bg][/color]
```

### Nesting Rules
- All graphics text tags can be freely nested.
- Each tag pushes its value onto a stack; the closing tag pops it, restoring the previous value.
- Tags from the **logging BBCode dialect** (e.g. `[b]`, `[i]`, `[c=...]`, `[if ...]`) are **not** recognised by the graphics text renderer and will be rendered as literal text.

### Predefined Color Names (Graphics Text)
| Name | RGB |
| :--- | :--- |
| `red` | `(1, 0, 0)` |
| `green` | `(0, 1, 0)` |
| `blue` | `(0, 0, 1)` |
| `yellow` | `(1, 1, 0)` |
| `orange` | `(1, 0.5, 0)` |
| `magenta` / `purple` | `(1, 0, 1)` |
| `cyan` | `(0, 1, 1)` |
| `white` | `(1, 1, 1)` |
| `black` | `(0, 0, 0)` |
| `gray` / `grey` | `(0.5, 0.5, 0.5)` |

---

## Logging vs. Graphics BBCode — Quick Reference

| Feature | Logging (`bbcode` package) | Graphics (`draw_text_bbcode_ttf`) |
| :--- | :--- | :--- |
| Output | ANSI terminal escape sequences | GPU vertex colors (Batch2D quads) |
| Foreground color tag | `[c=red]...[/c]` | `[color=red]...[/color]` |
| Background color tag | `[bg=red]...[/bg]` | `[bg=red]...[/bg]` |
| Opacity | ❌ Not supported | `[opacity=0.5]...[/opacity]` |
| Background opacity | ❌ Not supported | `[bg_opacity=0.5]...[/bg_opacity]` |
| Bold / italic / underline | ✅ `[b]`, `[i]`, `[u]`, `[s]` | ❌ Not supported |
| Conditional / tag functions | ✅ `[if]`, `[len]`, `[hour]` etc. | ❌ Not supported |
| Context variables | ✅ `[time]`, `[message]` etc. | ❌ Not supported |

---

## Nesting Examples

Tag functions can be nested within each other to achieve complex log layouts.

### 1. Conditional formatting based on message length:
```bbcode
[if [len [message]] > 20: "Message is too long!"]
```

### 2. Time-dependent styling:
Color-code or bold timestamps depending on the hour of the day:
```bbcode
[if [hour] < 20: [b][time][/b]]
```
*(Evaluates to a bold timestamp before 20:00, and empty/unformatted after).*

### 3. Nested string expressions:
```bbcode
[if [len [message]] > [len [time]]: [c=yellow]Message is longer than timestamp[/c]]
```

### 4. Ternary condition with else statement:
Display "Day" during daytime hours, and "Night" otherwise:
```bbcode
[if [hour] < 20: "Day" ? "Night"]
```

---

## Adding Custom Tag Functions

The tag functions engine is designed to be easily extensible. To register and implement your own custom tag functions:

### 1. Define your procedure
Create a new procedure that matches the `Tag_Func` prototype:
```odin
Tag_Func :: #type proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool)
```

Inside your procedure:
- Access the `Tag_Func_Context` fields (`enable_color`, `time_str`, `message_str`, etc.).
- Recursively evaluate the tag's inner arguments using `validate_and_format_bbcode` if you want to support nested tags within the argument string.
- Return the processed string allocated using the provided `allocator`, an error message if parsing fails, and a boolean success status.

**Example**: A simple prefixing tag `[prefix <text>]`:
```odin
tag_prefix :: proc(args: string, ctx: Tag_Func_Context, allocator: runtime.Allocator) -> (result: string, err_msg: string, ok: bool) {
	// 1. Evaluate arguments recursively to support nested tags
	evaluated, err, val_ok := validate_and_format_bbcode(
		args,
		ctx.enable_color,
		ctx.allow_variables,
		ctx.time_str,
		ctx.location_str,
		ctx.level_str,
		ctx.message_str,
		ctx.thread_id_str,
		allocator,
	)
	if !val_ok {
		return "", err, false
	}
	defer delete(evaluated, allocator)

	// 2. Prepend prefix to the formatted string
	return fmt.aprintf("PREFIX: %s", evaluated, allocator = allocator), "", true
}
```

### 2. Register your Tag Function
Register your custom tag handler dynamically at runtime (typically during application initialization) using the `bbcode.register_tag_func` function:

```odin
bbcode.register_tag_func("prefix", tag_prefix)
```

This dynamically registers the tag handler in a thread-safe global registry, meaning you do not need to modify the `bbcode` package source code to add new tags. If a tag with the same name already exists, it will be overridden by the new handler.

To free the memory allocated by dynamically registered tags at application shutdown, call:
```odin
bbcode.deinit_tag_funcs()
```

### 3. Usage
Your new tag function will be automatically matched, validated, and formatted by the engine:
```bbcode
[prefix hello [b]world[/b]]
```
*(Evaluates to `PREFIX: hello world` with `world` styled in bold when colors are enabled).*

---

## Escaping Bracket Syntax

Literal brackets (`[` or `]`) can be printed or used in templates without interpretation in two ways:

1. **Backslash Escaping**:
   To render a bracket without evaluating it, prefix it with a backslash `\`:
   - `\[` produces a literal `[`
   - `\]` produces a literal `]`
   - Example: `escaped \[b\]` prints `escaped [b]` without treating `b` as a bold tag.

2. **Double Brackets (Bracketed Evaluation)**:
   If you want to evaluate a variable/tag inside a template and wrap the resulting value in brackets, use double brackets `[[` and `]]`:
   - `[[time]]` evaluates the `time` variable and wraps the result in brackets (e.g. `[18:45:00]`).
   - `[[location]]` evaluates the `location` variable and wraps it in brackets (e.g. `[main.odin:12]`).

For example, if you want brackets around variables in a custom template, you can write:
```bbcode
[[time]] [[location]] [level]: [message]
```
This will be formatted to:
```
[18:45:00] [main.odin:12:main()] info: your log message
```

---

## Template Variables & Bracket Layouts

The formatting engine behaves differently depending on whether a **default layout** or a **custom template** is active:

1. **Default Layouts** (no custom template specified, or `format.template == ""`):
   - The framework automatically encapsulates variables (`[time]`, `[location]`, `[thread_id]`) in brackets with trailing spaces (e.g. `[18:45:00] ` or `[main.odin:12] `) to maintain a consistent structural layout.
   - The `[level]` variable includes a trailing colon (e.g. `info: `).

2. **Custom Templates** (`format.template != ""`):
   - Bracket encapsulations, colons, and trailing spaces are **omitted** by default. Variables are rendered as their raw value (e.g. `time` is rendered as `18:45:00`, `level` is rendered as `info`).
   - The layout author has full control and must explicitly define brackets and spacing in the template itself if they want them (e.g., using double brackets `[[time]]` or escaped brackets `\[[time]\]`).

---

## Tag Suppression

A custom `Log_Output` can specify a set of tags to suppress entirely during formatting by setting the `suppressed_tags` field:
- **Enum Values** (`logging.Log_Tag`): `Time`, `Location`, `Level`, `Message`, `Thread_Id`.
- **Bitset Type** (`logging.Log_Tags`).

When a tag is suppressed:
- The evaluation of the variable is skipped entirely.
- Both single-bracketed tags (e.g. `[location]`) and double-bracketed tags (e.g. `[[location]]`) are completely ignored and write nothing to the output (including any wrapping brackets).

For example, to suppress the `time` and `location` variables, you can set the `suppressed_tags` field on the output or pass it during creation:
```odin
// Option 1: Configure it when creating the output
output := logging.create_console_output(.Info, format, suppressed_tags = {.Time, .Location})

// Option 2: Set/modify it directly on the Log_Output structure at any time
output.suppressed_tags = {.Time, .Location}
```
This will be formatted and logged as:
```
info: your log message
```



