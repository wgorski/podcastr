import 'package:flutter/material.dart';
import '../models/track.dart';

const seedTracks = <Track>[
  Track(
    id: 't1',
    title: 'The Hidden Logic of Cities',
    channel: 'Wrong Turn',
    duration: 3287,
    size: '47.2 MB',
    addedAt: 'Today',
    color1: Color(0xFFF0A868),
    color2: Color(0xFFC9622E),
  ),
  Track(
    id: 't2',
    title: 'How Submarines Hear the Ocean',
    channel: 'Practical Physics',
    duration: 1842,
    size: '26.4 MB',
    addedAt: 'Today',
    color1: Color(0xFF6AB7FF),
    color2: Color(0xFF2D6BB8),
  ),
  Track(
    id: 't3',
    title: 'Why Memory Fails Us (and Helps Us)',
    channel: 'The Long Take',
    duration: 4521,
    size: '64.8 MB',
    addedAt: 'Yesterday',
    color1: Color(0xFFB794FF),
    color2: Color(0xFF7558C4),
  ),
  Track(
    id: 't4',
    title: 'Building a Pizza Oven in 48 Hours',
    channel: 'Slow Build',
    duration: 1156,
    size: '16.5 MB',
    addedAt: 'Yesterday',
    color1: Color(0xFFFF6B5B),
    color2: Color(0xFFC4382B),
  ),
  Track(
    id: 't5',
    title: 'Ambient Soundscapes for Deep Work',
    channel: 'Field Notes',
    duration: 5400,
    size: '77.4 MB',
    addedAt: '3 days ago',
    color1: Color(0xFF5EE3D4),
    color2: Color(0xFF2A9D8F),
  ),
  Track(
    id: 't6',
    title: 'The Economics of Bus Routes',
    channel: 'Roundabout',
    duration: 2734,
    size: '39.2 MB',
    addedAt: 'Last week',
    color1: Color(0xFFF5D96C),
    color2: Color(0xFFB89934),
  ),
  Track(
    id: 't7',
    title: 'Letters from a Lighthouse Keeper',
    channel: 'Wrong Turn',
    duration: 2890,
    size: '41.4 MB',
    addedAt: 'Last week',
    color1: Color(0xFFFF8DB2),
    color2: Color(0xFFC25288),
  ),
];

const downloadPreview = Track(
  id: 'preview',
  title: 'The Hidden Logic of Cities',
  channel: 'Wrong Turn',
  duration: 2470,
  size: '35.4 MB',
  addedAt: 'Today',
  color1: Color(0xFFF0A868),
  color2: Color(0xFFC9622E),
);

const downloadSizes = {
  'high': '35.4 MB',
  'med': '21.1 MB',
  'low': '12.3 MB',
};
