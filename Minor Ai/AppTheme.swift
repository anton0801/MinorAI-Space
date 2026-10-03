//
//  AppTheme.swift
//  Minor Ai
//
//  Single source of truth for the per-sphere color palette, shared by
//  ContentView and ChatView. Hex values match the original inline logic.
//

import SwiftUI

struct AppTheme {
    let sphere: Int?

    init(sphere: Int?) {
        self.sphere = sphere
    }

    var background: Color {
        switch sphere {
        case 1: return Color(hex: "#121212")
        case 2: return Color(hex: "#1B1420")
        case 3: return Color(hex: "#101317")
        case 4: return Color(hex: "#171010")
        case 5: return Color(hex: "#0E0F17")
        case 6: return Color(hex: "#17100E")
        default: return Color(red: 18/255, green: 18/255, blue: 18/255)
        }
    }

    var chatRectangle: Color {
        switch sphere {
        case 1: return Color(hex: "#252525")
        case 2: return Color(hex: "#1D1822")
        case 3: return Color(hex: "#181C22")
        case 4: return Color(hex: "#211919")
        case 5: return Color(hex: "#191921")
        case 6: return Color(hex: "#211D19")
        default: return Color(red: 37/255, green: 37/255, blue: 37/255)
        }
    }

    var chatStroke: Color {
        switch sphere {
        case 1: return Color(hex: "#6A6A6A")
        case 2: return Color(hex: "#513F5F")
        case 3: return Color(hex: "#3F4D5F")
        case 4: return Color(hex: "#5F3F40")
        case 5: return Color(hex: "#5A3F5F")
        case 6: return Color(hex: "#5F4C3F")
        default: return Color(red: 106/255, green: 106/255, blue: 106/255)
        }
    }

    var placeholderText: Color {
        switch sphere {
        // #8C8C8C keeps placeholders above 4.5:1 contrast on every theme's input field.
        case 1: return Color(hex: "#8C8C8C")
        case 2: return Color(hex: "#B4B4B4")
        case 3: return Color(hex: "#8C8C8C")
        case 4: return Color(hex: "#8C8C8C")
        case 5: return Color(hex: "#8C8C8C")
        case 6: return Color(hex: "#8C8C8C")
        default: return Color(red: 150/255, green: 150/255, blue: 150/255)
        }
    }

    var blur: Color {
        switch sphere {
        case 1: return Color(hex: "#BBFFDF").opacity(0.3)
        case 2: return Color(hex: "#E1BEFF").opacity(0.3)
        case 3: return Color(hex: "#BEFFF7").opacity(0.3)
        case 4: return Color(hex: "#FC86C3").opacity(0.3)
        case 5: return Color(hex: "#FC86C3").opacity(0.3)
        case 6: return Color(hex: "#FC9886").opacity(0.3)
        default: return Color(red: 187/255, green: 255/255, blue: 223/255).opacity(0.3)
        }
    }

    // "Minor Plus" pill uses the same fill/stroke as the chat rectangle.
    var minorPlusRectangle: Color { chatRectangle }
    var minorPlusStroke: Color { chatStroke }
}
