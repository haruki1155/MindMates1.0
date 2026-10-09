import 'package:flutter/material.dart';
import '../models/intervention_models.dart';

class InterventionGroundingScreen extends StatefulWidget { const InterventionGroundingScreen({super.key}); @override State<InterventionGroundingScreen> createState()=>_InterventionGroundingScreenState(); }
class _InterventionGroundingScreenState extends State<InterventionGroundingScreen> {
  static const _steps=['Notice five things you can see.','Notice four things you can feel.','Notice three things you can hear.','Notice two things you can smell.','Notice one thing you can taste, or another comfortable sensory detail.']; int _index=0;
  void _finish(InterventionOutcome value)=>Navigator.pop(context,value);
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Grounding exercise')),body:SafeArea(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text('Step ${_index+1} of 5'),const SizedBox(height:24),Text(_steps[_index],style:Theme.of(context).textTheme.headlineSmall),const Spacer(),Row(children:[OutlinedButton(onPressed:_index==0?null:()=>setState(()=>_index--),child:const Text('Previous')),const Spacer(),TextButton(onPressed:()=>_finish(InterventionOutcome.skipped),child:const Text('Skip')),const SizedBox(width:8),FilledButton(onPressed:()=>_index==4?_finish(InterventionOutcome.completed):setState(()=>_index++),child:Text(_index==4?'Finish':'Next'))])])))); }
