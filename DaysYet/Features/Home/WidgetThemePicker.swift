import SwiftUI

/// Each choice is a live preview of the same widget, changing only its theme.
struct WidgetThemePicker<Preview: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selectedTheme: WidgetTheme
    let previewSize: CGSize
    let onSelect: (WidgetTheme) -> Void
    @ViewBuilder let preview: (WidgetTheme) -> Preview

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.adaptive(minimum: 150), spacing: 12)],
            spacing: 12
        ) {
            ForEach(WidgetTheme.allCases) { theme in
                Button {
                    onSelect(theme)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { geometry in
                            preview(theme)
                                .environment(\.dynamicTypeSize, .medium)
                                .frame(width: previewSize.width, height: previewSize.height)
                                .scaleEffect(geometry.size.width / previewSize.width, anchor: .topLeading)
                        }
                        .aspectRatio(previewSize.width / previewSize.height, contentMode: .fit)
                        .clipped()
                        .accessibilityHidden(true)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(theme.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: selectedTheme == theme ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTheme == theme ? Color.accentColor : Color.secondary)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
                    .padding(6)
                    .background(DaysYetTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(selectedTheme == theme ? Color.accentColor : Color.secondary.opacity(0.2),
                                          lineWidth: selectedTheme == theme ? 2 : 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityValue(selectedTheme == theme ? L10n.text("選択中", "Selected") : "")
                .accessibilityAddTraits(selectedTheme == theme ? .isSelected : [])
                .accessibilityHint(L10n.text("このテーマを使います", "Use this theme"))
                .accessibilityIdentifier("widget.theme.\(theme.rawValue)")
            }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 360 : 720)
        .frame(maxWidth: .infinity)
    }
}
