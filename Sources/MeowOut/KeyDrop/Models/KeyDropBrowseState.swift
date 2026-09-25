// Sources/MeowOut/KeyDrop/Models/KeyDropBrowseState.swift
import Foundation
import Observation

/// 常用语列表页的浏览状态：当前分类与搜索词。
///
/// 推进到编辑页时列表视图会离开视图树，它自己的 @State 随之丢失；把这两项提到
/// 由设置窗口持有的 observable 上，用户从某条常用语返回列表时筛选与搜索词才不会丢。
@Observable
final class KeyDropBrowseState {
    var selectedCategory: String = KeyDropConstants.categoryAll
    var searchText: String = ""
}
