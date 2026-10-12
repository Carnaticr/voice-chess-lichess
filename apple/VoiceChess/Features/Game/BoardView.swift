import SwiftUI
import VoiceChessCore

/// Tap-to-move chessboard using the Lichess "cburnett" piece artwork from the asset catalog.
struct BoardView: View {
    let position: Position
    let orientation: PieceColor
    let lastMove: Move?
    let selected: Square?
    let targets: Set<Square>
    let theme: BoardTheme
    let onTap: (Square) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let sq = square(row: row, col: col)
                            SquareView(
                                square: sq,
                                piece: position[sq],
                                theme: theme,
                                isLastMove: lastMove?.from == sq || lastMove?.to == sq,
                                isSelected: selected == sq,
                                isTarget: targets.contains(sq),
                                isCheckedKing: isCheckedKing(sq),
                                showRank: col == 0,
                                showFile: row == 7,
                                cell: cell
                            )
                            .onTapGesture { onTap(sq) }
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func square(row: Int, col: Int) -> Square {
        let file = orientation == .white ? col : 7 - col
        let rank = orientation == .white ? 7 - row : row
        return Square(index: rank * 8 + file)
    }

    private func isCheckedKing(_ sq: Square) -> Bool {
        guard let p = position[sq], p.kind == .king, p.color == position.sideToMove else { return false }
        return position.inCheck
    }
}

private struct SquareView: View {
    let square: Square
    let piece: Piece?
    let theme: BoardTheme
    let isLastMove: Bool
    let isSelected: Bool
    let isTarget: Bool
    let isCheckedKing: Bool
    let showRank: Bool
    let showFile: Bool
    let cell: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(square.isLight ? theme.light : theme.dark)
            if isLastMove { Rectangle().fill(theme.lastMove) }
            if isSelected { Rectangle().fill(Color.green.opacity(0.45)) }
            if isCheckedKing {
                RadialGradient(colors: [.red, .red.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: cell * 0.6)
            }
            if let piece {
                Image(piece.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(cell * 0.02)
            }
            if isTarget {
                if piece == nil {
                    Circle().fill(Color.green.opacity(0.45)).frame(width: cell * 0.28, height: cell * 0.28)
                } else {
                    Circle().strokeBorder(Color.green.opacity(0.5), lineWidth: cell * 0.08)
                }
            }
            coordinates
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isTarget ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var coordinates: some View {
        let ink = square.isLight ? theme.dark : theme.light
        if showRank {
            Text("\(square.rankNumber)")
                .font(.system(size: cell * 0.17, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(cell * 0.04)
                .accessibilityHidden(true)
        }
        if showFile {
            Text(String(square.fileLetter))
                .font(.system(size: cell * 0.17, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(cell * 0.04)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityText: String {
        guard let piece else { return square.name }
        return "\(square.name), \(piece.color.rawValue) \(piece.kind.name)"
    }
}

#Preview {
    BoardView(position: .start, orientation: .white, lastMove: nil, selected: Square("e2"),
              targets: Set([Square("e3"), Square("e4")].compactMap { $0 }),
              theme: .brown, onTap: { _ in })
        .padding()
}
