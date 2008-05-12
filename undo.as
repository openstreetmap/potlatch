
	// =====================================================================================
	// undo.as
	// Potlatch undo stack code
	// =====================================================================================

	function UndoStack() {
		this.sp=0;
	};

	UndoStack.prototype=new Array();

	UndoStack.prototype.append=function(task,params,tooltip) {
		// add to stack
		if (_root.undoing) { return; }
		this[this.sp]=new Array(task,params,tooltip); this.sp++;
		this.setTooltip(tooltip);
	};

	UndoStack.prototype.rollback=function() {
		if (_root.undoing) { return; }		// Stop any routines from adding to the
		_root.undoing=true;					//  | undo stack
		if (this.sp==0) { return; }
		var popped=this[this.sp-1];			// Same as this.pop, but works :)
		this.sp--;							//	|
		popped[0].call(this,popped[1]);
		if (this.sp)	 { this.setTooltip(this[this.sp-1][2]); }
					else { this.setTooltip(""); }
		_root.undoing=false;				// Permit adding to undo stack
	};

	UndoStack.prototype.setTooltip=function(str) {
		if (str=='') {
			_root.panel.i_undo.onRollOver=function() { setFloater("Nothing to undo"); };
			_root.panel.i_undo._alpha=50;
		} else {
			_root.panel.i_undo.onRollOver=function() { setFloater("Undo "+str+" (Z)"); };
			_root.panel.i_undo._alpha=100;
		}
	};
	
	UndoStack.prototype.clear=function() { this.sp=0; };

	// ----	Individual undo methods
	
	//		Added point into way

	UndoStack.prototype.undo_addpoint=function(params) {
		var waylist=params[0]; var poslist=params[1]; var w;
		for (var i in waylist) {
			w=waylist[i];
			w.removeAnchorPoint(poslist[i]);
			w.clean=false;
		}
		w.select();
		stopDrawing();
	};

	//		Moved node
	
	UndoStack.prototype.undo_movenode=function(params) {
		var w=moveNode(params[0],params[1],params[2],undefined);
		if (w) { 
			_root.map.ways[w].clean=false;
			_root.map.ways[w].select();
		}
	};
	
	//		Merged ways

	UndoStack.prototype.undo_mergeways=function(params) {
		var way=params[0];
		if (way) {
			way.attr=params[1];
			way.splitWay(params[3],params[2]);
		} else {
			handleError(-1,new Array("Way "+way+" cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear();
		}
	};

	//		Split way

	UndoStack.prototype.undo_splitway=function(params) {
		var way1=params[0]; var way2=params[1];
		if (way1.mergeAtCommonPoint(way2)) {
			way2.redraw(); way2.select();
		} else {
			handleError(-1,new Array("Ways "+way1+" and "+way2+" don't share a common point any more, so I can't undo the split."));
			this.clear();
		}
	};

	//		Changed tags
	//		** to do - relations support
	
	UndoStack.prototype.undo_waytags=function(params) {
		var way=params[0]; if (!way) {
			handleError(-1,new Array("Way "+way+" cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear(); return;
		} else {
			way.attr=params[1];
			way.clean=false;
			way.redraw();
			way.select();
		}
	};
	UndoStack.prototype.undo_pointtags=function(params) {
		var way=params[0]; var point=params[1]; if (!way) {
			handleError(-1,new Array("Way "+way+" cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear(); return;
		} else {
			way.path[point][4]=params[2];
			way.clean=false;
			way.select(); _root.map.anchors[point].select();
		}
	};
	UndoStack.prototype.undo_poitags=function(params) {
		var poi=params[0]; if (!poi) {
			handleError(-1,new Array("The POI cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear(); return;
		} else {
			poi.attr=params[1];
			poi.clean=false;
			poi.select();
		}
	};
	
	//		Removed point from way(s) (at x,y,tags if it no longer exists)

	UndoStack.prototype.undo_deletepoint=function(params) {
		var paramid=params[0]; var x=params[1]; var y=params[2]; var attr=params[3];
		var id=undefined;
		var qway,last;
		// look if node is used in any other ways, take it from there if so
		for (qway in _root.map.ways) {
			for (qs=0; qs<_root.map.ways[qway].path.length; qs+=1) {
				if (_root.map.ways[qway].path[qs][2]==paramid) {
					id=paramid;
					x=_root.map.ways[qway].path[qs][0];
					y=_root.map.ways[qway].path[qs][1];
					attr=_root.map.ways[qway].path[qs][4];
				}
			}
		}
		if (!id) { _root.newnodeid--; id=newnodeid; }
		// reinstate at each place
		var waylist=params[4];
		var poslist=params[5];
		var newpoint=new Array(x,y,id,1,attr,0);
		for (qway in waylist) {
			_root.map.ways[waylist[qway]].path.splice(poslist[qway],0,newpoint);
			_root.map.ways[waylist[qway]].clean=false;
			_root.map.ways[waylist[qway]].redraw();
			last=waylist[qway];	// select last one
		}
		stopDrawing();
		_root.map.ways[last].select();
	};

	//		Moved POI

	UndoStack.prototype.undo_movepoi=function(params) {
		var poi=params[0]; if (!poi) {
			handleError(-1,new Array("The POI cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear(); return;
		} else {
			poi._x=params[1]; poi._y=params[2];
			poi.clean=false; poi.select();
		}
	};

	//		Moved way (and any nodes used in other ways)

	UndoStack.prototype.undo_movenodes=function(params) {
		var way=params[0]; if (!way) {
			handleError(-1,new Array("Way "+way+" cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear(); return;
		} else {
			way.moveNodes(-params[1],-params[2]);
			way.redraw();
			way.select();
		}
	};

	//		Reversed way

	UndoStack.prototype.undo_reverse=function(params) {
		var way=params[0]; if (!way) {
			handleError(-1,new Array("Way "+way+" cannot be found (perhaps you've panned away?) so I can't undo."));
			this.clear(); return;
		} else {
			way.reverseWay();
		}
	};

	//		Deleted POI

	UndoStack.prototype.undo_deletepoi=function(params) {
		var poi=params[0];
		stopDrawing();
		if (_root.map.pois[poi]) {} else {
			_root.map.pois.attachMovie("poi",poi,++poidepth);
		}
		_root.map.pois[poi]._x=params[1];
		_root.map.pois[poi]._y=params[2];
		_root.map.pois[poi].attr=params[3];
		_root.map.pois[poi].select();
		_root.map.pois[poi].clean=false;
		markClean(false);
	};
	
	//		Deleted way

	UndoStack.prototype.undo_deleteway=function(params) {
		var way=params[0];
		stopDrawing();
		_root.map.ways.attachMovie("way",way,++waydepth);
		_root.map.ways[way]._x=params[1];
		_root.map.ways[way]._y=params[2];
		_root.map.ways[way].attr=params[3];
		_root.map.ways[way].path=params[4];
		_root.map.ways[way].redraw();
		_root.map.ways[way].select();
		_root.map.ways[way].clean=false;
		markClean(false);
	};

	//		Created POI

	UndoStack.prototype.undo_createpoi=function(params) {
		poi=params[0]; poi.remove();
		markClean(false);
	};


	// Trace stuff - not used
	// from .append
// _root.chat.text="Stack now "+l;
// _root.chat.text+="\nAppended "+task+","+params;
	// from .rollback
// _root.chat.text="Stack was "+this.length+"\n";
// _root.chat.text+="rollback\npopped: "+popped[0]+";"+popped[1]+";"+popped[2]+"\n";
// _root.chat.text+="\nStack now "+this.length;
