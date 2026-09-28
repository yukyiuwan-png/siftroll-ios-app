//
//  AlbumPickerView.swift
//  SiftRoll
//
//  Sheet listing the automatic albums: "All Photos", then one section per year
//  (newest first) with a "whole year" row followed by its months.
//

import SwiftUI
import Photos

struct AlbumPickerView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    let yearAlbums: [YearAlbum]
    let libraryCount: Int
    let selected: AlbumSelection
    let onSelect: (AlbumSelection) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    albumRow(title: l10n.t("album.all"),
                             count: libraryCount,
                             cover: yearAlbums.first?.cover,
                             icon: "photo.on.rectangle.angled",
                             selection: .all)
                } footer: {
                    Text(l10n.t("album.picker.subtitle"))
                }

                ForEach(yearAlbums) { year in
                    Section {
                        albumRow(title: l10n.t("album.wholeYear"),
                                 count: year.count,
                                 cover: year.cover,
                                 icon: "calendar",
                                 selection: year.selection)

                        ForEach(year.months) { month in
                            albumRow(title: month.selection.title(locale: l10n.language.locale) ?? "",
                                     count: month.count,
                                     cover: month.cover,
                                     icon: nil,
                                     selection: month.selection)
                        }
                    } header: {
                        Text(year.selection.title(locale: l10n.language.locale) ?? String(year.year))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle(l10n.t("album.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n.t("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .overlay {
                if yearAlbums.isEmpty && libraryCount == 0 {
                    ContentUnavailableView(l10n.t("deck.empty.title"),
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text(l10n.t("deck.empty.message")))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func albumRow(title: String,
                          count: Int,
                          cover: PHAsset?,
                          icon: String?,
                          selection: AlbumSelection) -> some View {
        let isSelected = selection == selected
        return Button {
            Haptics.impact(.light)
            onSelect(selection)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                AssetThumbnailView(asset: cover, size: 48)
                    .overlay(alignment: .bottomTrailing) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .bold))
                                .padding(4)
                                .background(Color.brandPrimary, in: Circle())
                                .foregroundStyle(.white)
                                .offset(x: 4, y: 4)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.white)
                    Text(l10n.t("album.photoCount", count.formatted(.number.locale(l10n.language.locale))))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.brandPrimary)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(isSelected ? Color.brandPrimary.opacity(0.12) : Color.white.opacity(0.06))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
