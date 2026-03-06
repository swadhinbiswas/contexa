# Cortexa Documentation

This folder contains the web-based documentation for Cortexa.

## Viewing the Documentation

Simply open `index.html` in a web browser:

```bash
# Using Python's built-in server
cd DOCS
python3 -m http.server 8000
# Then open http://localhost:8000
```

Or directly open the file in your browser:

```
file:///path/to/cortexa/DOCS/index.html
```

## Features

- 🎨 Beautiful dark theme with purple/blue gradient accents
- 📱 Fully responsive design
- ⚡ Smooth animations and transitions
- 🧠 Nerd Font icons for terminal aesthetics
- 📦 Installation tabs for all 7 supported languages
- 📊 Performance metrics from the GCC paper

## Customization

The documentation uses CSS variables for easy theming:

```css
:root {
    --bg-primary: #0d1117;
    --accent-primary: #58a6ff;
    --gradient-start: #6366f1;
    --gradient-end: #8b5cf6;
}
```

Edit these values in the `<style>` section to customize the look.
