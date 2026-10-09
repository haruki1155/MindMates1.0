import 'dart:async';
import 'package:flutter/material.dart';
import '../models/intervention_models.dart';

class InterventionBreathingScreen extends StatefulWidget { const InterventionBreathingScreen({super.key}); @override State<InterventionBreathingScreen> createState()=>_InterventionBreathingScreenState(); }
class _InterventionBreathingScreenState extends State<InterventionBreathingScreen> with SingleTickerProviderStateMixin {
  Timer? _timer; late final AnimationController _animation; int _seconds=4,_phase=0,_cycles=0; bool _paused=false,_hold=true;
  String get _label=>['Inhale','Exhale','Hold'][_phase];
  @override void initState(){super.initState();_animation=AnimationController(vsync:this,duration:const Duration(seconds:4))..forward();_timer=Timer.periodic(const Duration(seconds:1),(_)=>_tick());}
  void _tick(){if(_paused)return;if(_seconds>1){setState(()=>_seconds--);return;}if(_phase==2&&++_cycles==5){Navigator.pop(context,InterventionOutcome.completed);return;}setState((){_phase=(_phase+1)%(_hold?3:2);_seconds=4;});_animation.forward(from:0);}
  @override void dispose(){_timer?.cancel();_animation.dispose();super.dispose();}
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Breathing exercise')),body:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[ScaleTransition(scale:Tween(begin:.7,end:1.15).animate(_animation),child:CircleAvatar(radius:90,child:Text('$_seconds',style:const TextStyle(fontSize:48)))),const SizedBox(height:24),Text('$_label · Cycle ${_cycles+1} of 5'),SwitchListTile(title:const Text('Include comfortable hold'),value:_hold,onChanged:(v)=>setState(()=>_hold=v)),Wrap(spacing:12,children:[OutlinedButton(onPressed:()=>Navigator.pop(c,InterventionOutcome.skipped),child:const Text('Skip')),FilledButton(onPressed:()=>setState(()=>_paused=!_paused),child:Text(_paused?'Resume':'Pause')),TextButton(onPressed:(){setState((){_phase=0;_seconds=4;_cycles=0;});_animation.forward(from:0);},child:const Text('Restart'))])]))); }
