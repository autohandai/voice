# Autohand Voice Assets

## Required for .app builds

| File | Size | Purpose |
|------|------|---------|
| `autohand-voice.icns` | — | App icon (convert from 1024×1024 PNG) |
| `menubar-icon.png` | 22×22 | Menu bar icon (template image, single color) |
| `menubar-icon@2x.png` | 44×44 | Menu bar icon retina |
| `dmg-background.png` | 600×400 | DMG installer background |

## Generate .icns from PNG

```bash
# Start with a 1024×1024 PNG named icon-1024.png
mkdir autohand-voice.iconset
for size in 16 32 128 256 512; do
    sips -z $size $size icon-1024.png --out autohand-voice.iconset/icon_${size}x${size}.png
    sips -z $((size*2)) $((size*2)) icon-1024.png --out autohand-voice.iconset/icon_${size}x${size}@2x.png
done
iconutil -c icns autohand-voice.iconset
rm -rf autohand-voice.iconset
```

## Icon Design Notes

- **App icon**: Microphone + sound wave, clean, recognizable at 16px
- **Menu bar icon**: Simple silhouette, works on light + dark menu bars
- **Template image**: Use a single color (black) with transparency — macOS auto-adapts for dark mode
