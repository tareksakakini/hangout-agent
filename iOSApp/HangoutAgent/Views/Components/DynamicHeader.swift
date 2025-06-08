import SwiftUI

struct DynamicHeader: View {
    let title: String
    let scrollOffset: CGFloat
    let rightButton: (() -> AnyView)?
    
    // Constants
    private let minHeight: CGFloat = 44
    private let maxHeight: CGFloat = 100
    private let minScale: CGFloat = 0.8
    private let maxScale: CGFloat = 1.2
    private let minOffset: CGFloat = 0
    private let maxOffset: CGFloat = 20
    
    init(title: String, scrollOffset: CGFloat, rightButton: (() -> AnyView)? = nil) {
        self.title = title
        self.scrollOffset = scrollOffset
        self.rightButton = rightButton
    }
    
    private var headerHeight: CGFloat {
        let difference = maxHeight - minHeight
        let reduction = min(max(scrollOffset, 0), difference)
        return maxHeight - reduction
    }
    
    private var titleScale: CGFloat {
        let difference = maxScale - minScale
        let progress = min(max(scrollOffset / 50, 0), 1)
        return maxScale - (progress * difference)
    }
    
    private var titleOffset: CGFloat {
        let progress = min(max(scrollOffset / 3, 0), 1)
        return -(progress * maxOffset)
    }
    
    private var backgroundOpacity: CGFloat {
        min(scrollOffset / 50, 1)
    }
    
    private var buttonOpacity: CGFloat {
        1 - min(scrollOffset / 30, 1)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            
            HStack {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .scaleEffect(titleScale)
                    .offset(y: titleOffset)
                
                Spacer()
                
                if let rightButton = rightButton {
                    rightButton()
                        .opacity(buttonOpacity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(height: headerHeight)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
} 