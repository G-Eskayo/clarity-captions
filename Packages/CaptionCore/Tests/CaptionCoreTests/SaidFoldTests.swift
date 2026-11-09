import CaptionCore
import Testing

/// #246, the owner's answer on PR #255: every translated caption is folded (C). A line shows just its translation;
/// a tap shows what was said underneath and another tap hides it again. These try to break that fold.
struct SaidFoldTests {
    @Test func everyLineStartsFolded() {
        let fold = SaidFold()
        #expect(!fold.isOpen(0))
        #expect(!fold.isOpen(41))
        #expect(!fold.isOpen(-1))
    }

    @Test func aTapShowsWhatWasSaidAndASecondTapHidesIt() {
        var fold = SaidFold()
        let changed1 = fold.tap(3)
        #expect(changed1)
        #expect(fold.isOpen(3))
        let changed2 = fold.tap(3)
        #expect(changed2)
        #expect(!fold.isOpen(3))
    }

    @Test func manyTapsAlternateAndNeverStick() {
        var fold = SaidFold()
        for n in 1...51 { fold.tap(7); #expect(fold.isOpen(7) == !n.isMultiple(of: 2)) }
        #expect(fold.isOpen(7))   // 51 taps: odd, so open
        #expect(fold.opened == [7])
    }

    @Test func aTapOpensOnlyThatLine() {
        var fold = SaidFold()
        fold.tap(1)
        fold.tap(2)
        fold.tap(1)
        #expect(!fold.isOpen(1))
        #expect(fold.isOpen(2))
        #expect(!fold.isOpen(3))
    }

    @Test func aTapWhileWordsAreSelectedOnlyLetsGoOfTheSelection() {
        // #107: a tap with a selection held clears the selection; it mustn't also fold or unfold the line under it.
        var fold = SaidFold()
        let changed3 = fold.tap(4, selecting: true)
        #expect(!changed3)
        #expect(!fold.isOpen(4))
        fold.tap(4)
        let changed4 = fold.tap(4, selecting: true)
        #expect(!changed4)
        #expect(fold.isOpen(4))
    }

    @Test func linesThatAreGoneCloseSoANewConversationStartsFolded() {
        // Line ids start again at 0 in a new conversation: an old opened id must not open the new line that reuses it.
        var fold = SaidFold()
        fold.tap(0)
        fold.tap(5)
        fold.keep(only: [5, 6])
        #expect(!fold.isOpen(0))
        #expect(fold.isOpen(5))
        fold.keep(only: [])
        #expect(fold.opened.isEmpty)
        #expect(!fold.isOpen(5))
    }

    @Test func keepingIsSafeToRepeatAndWithIdsNeverOpened() {
        var fold = SaidFold()
        fold.tap(2)
        fold.keep(only: [2, 2, 9, -3])
        fold.keep(only: [2, 2, 9, -3])
        #expect(fold.opened == [2])
    }

    @Test func aFoldCanStartWithALineOpened() {
        // The screenshot demo opens one line so the picture shows both states.
        var fold = SaidFold(opened: [8])
        #expect(fold.isOpen(8))
        fold.tap(8)
        #expect(!fold.isOpen(8))
    }
}
