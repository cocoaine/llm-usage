import Foundation

func tokenText(_ value: Int64) -> String {
    value.formatted(.number.grouping(.automatic))
}
