import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'hiker_rule.dart';

Widget _miniAppCover(String picUrl) {
  if (picUrl.isEmpty) {
    return Container(color: Colors.grey[300]);
  }
  return Image.network(
    picUrl,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) {
      return Container(color: Colors.grey[300]);
    },
  );
}

class MiniAppMovieGrid extends StatelessWidget {
  const MiniAppMovieGrid({
    super.key,
    required this.cards,
    required this.columns,
    this.onTap,
  });

  final List<MiniAppCard> cards;
  final int columns;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.72,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return InkWell(
          onTap: onTap == null ? null : () => onTap!(card.url),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _miniAppCover(card.picUrl)),
              const SizedBox(height: 6),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (card.desc.isNotEmpty)
                Text(
                  card.desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        );
      },
    );
  }
}

class MiniAppTextList extends StatelessWidget {
  const MiniAppTextList({super.key, required this.cards, this.onTap});

  final List<MiniAppCard> cards;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return InkWell(
          onTap: onTap == null ? null : () => onTap!(card.url),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.title),
                if (card.desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    card.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class MiniAppIconGrid extends StatelessWidget {
  const MiniAppIconGrid({super.key, required this.cards, this.onTap});

  final List<MiniAppCard> cards;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return InkWell(
          onTap: onTap == null ? null : () => onTap!(card.url),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                color: Colors.grey[300],
                child: const Icon(Icons.apps),
              ),
              const SizedBox(height: 8),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

class MiniAppDetailView extends StatelessWidget {
  const MiniAppDetailView({
    super.key,
    required this.card,
    this.episodes = const [],
    this.onEpisodeTap,
  });

  final MiniAppCard card;
  final List<String> episodes;
  final ValueChanged<String>? onEpisodeTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                Positioned.fill(
                  child: card.picUrl.isEmpty
                      ? Container(color: Colors.grey[300])
                      : ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 18,
                            sigmaY: 18,
                          ),
                          child: Image.network(
                            card.picUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(color: Colors.grey[300]);
                            },
                          ),
                        ),
                ),
                Center(
                  child: SizedBox(
                    width: 120,
                    height: 170,
                    child: _miniAppCover(card.picUrl),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '简介',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(card.desc),
                if (episodes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '选集',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: episodes.map((episode) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: onEpisodeTap == null
                                ? null
                                : () => onEpisodeTap!(episode),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(episode),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
