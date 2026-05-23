import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var store = SnippetStore.shared
    @ObservedObject var viewModel: PanelViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, weight: .medium))
                    Text(viewModel.searchText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.05))
                
                Divider()
            }
            
            // Category tab bar (horizontal scroll)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.categories, id: \.self) { category in
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                viewModel.selectedCategory = category
                                viewModel.selectIndex(0, scroll: true)
                            }
                        }) {
                            Text(category)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    ZStack {
                                        if viewModel.selectedCategory == category {
                                            Capsule()
                                                .fill(Color.accentColor)
                                                .shadow(color: Color.accentColor.opacity(0.3), radius: 3, x: 0, y: 1)
                                        } else {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.06))
                                        }
                                    }
                                )
                                .foregroundColor(viewModel.selectedCategory == category ? .white : .primary.opacity(0.8))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.03), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            
            Divider()
            
            let snippets = viewModel.filteredSnippets
            
            if snippets.isEmpty {
                VStack {
                    Spacer()
                    Text(store.snippets.isEmpty ? "尚无常用语，请在设置中添加" : "无匹配结果")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                                Button(action: {
                                    FloatingPanelController.shared.inject(snippet: snippet)
                                }) {
                                    SnippetRow(
                                        snippet: snippet,
                                        index: index,
                                        isSelected: index == viewModel.selectedIndex
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(index)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    if hovering {
                                        viewModel.selectIndex(index, scroll: false)
                                    }
                                }
                            }
                        }
                        .padding(8)
                      }
                      .onChange(of: viewModel.shouldScroll) { _, should in
                          if should {
                              withAnimation(.easeOut(duration: 0.1)) {
                                  proxy.scrollTo(viewModel.selectedIndex, anchor: .center)
                              }
                              viewModel.shouldScroll = false
                          }
                      }
                  }
              }
          }
          .frame(width: 320, height: 400, alignment: .top)
          .background(Color(nsColor: .windowBackgroundColor).opacity(0.1))
      }
  }

  struct SnippetRow: View {
      let snippet: Snippet
      let index: Int
      let isSelected: Bool
      
      var body: some View {
          HStack(spacing: 12) {
              if index < 9 {
                  Text("⌘\(index + 1)")
                      .font(.system(size: 9, weight: .bold))
                      .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary.opacity(0.6))
                      .frame(width: 22, height: 16)
                      .background(
                          RoundedRectangle(cornerRadius: 4)
                              .fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.04))
                      )
              } else {
                  Spacer().frame(width: 22)
              }
              
              VStack(alignment: .leading, spacing: 3) {
                  Text(snippet.title)
                      .font(.system(size: 13, weight: .semibold))
                      .foregroundColor(isSelected ? .white : .primary)
                  
                  Text(snippet.content)
                      .font(.system(size: 11, weight: .regular))
                      .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                      .lineLimit(1)
              }
              
              Spacer()
              
              if isSelected {
                  Image(systemName: "return")
                      .font(.system(size: 10, weight: .bold))
                      .foregroundColor(.white.opacity(0.8))
              }
          }
          .padding(.vertical, 8)
          .padding(.horizontal, 12)
          .background(
              ZStack {
                  if isSelected {
                      LinearGradient(
                          gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)]),
                          startPoint: .topLeading,
                          endPoint: .bottomTrailing
                      )
                      .cornerRadius(8)
                      .shadow(color: Color.accentColor.opacity(0.25), radius: 4, x: 0, y: 2)
                  } else {
                      Color.clear
                  }
              }
          )
          .overlay(
              RoundedRectangle(cornerRadius: 8)
                  .stroke(isSelected ? Color.white.opacity(0.15) : Color.primary.opacity(0.02), lineWidth: 1)
          )
          .contentShape(Rectangle())
      }
  }
