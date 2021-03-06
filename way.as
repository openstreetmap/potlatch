
	// =====================================================================================
	// OOP classes - OSMWay

	// ----	Initialise
	
	function OSMWay() {
		this.resetBBox();
		this.path=new Array();			// list of nodes
		this.attr=new Array();			// hash of tags
		this.mergedways=new Array();	// list of ways merged into this
		this.deletednodes=new Object();	// hash of nodes deleted from this
	};

	OSMWay.prototype=new MovieClip();
	OSMWay.prototype.clean=true;				// altered since last upload?
	OSMWay.prototype.uploading=false;			// currently uploading?
	OSMWay.prototype.locked=false;				// locked against upload?
	OSMWay.prototype.version=0;					// version number?
	OSMWay.prototype.uid=0;						// user ID (used for TIGER detection)
	OSMWay.prototype.historic=false;			// is this an undeleted, not-uploaded way?
	OSMWay.prototype.checkconnections=false;	// check shared nodes on reload

	// ----	Load from remote server

	OSMWay.prototype.load=function() {
		responder = function() { };
		responder.onResult = function(result) {
			_root.waysreceived+=1;
			var code=result.shift(); var msg=result.shift(); if (code) { handleError(code,msg,result); return; }
			var w=result[0];
			if (length(result[1])==0) { removeMovieClip(_root.map.ways[w]); 
										removeMovieClip(_root.map.areas[w]); return; }
			var i,id,x,y,prepoint,redrawws,l,n,b;
			_root.map.ways[w].clean=true;
			_root.map.ways[w].locked=false;
			_root.map.ways[w].historic=false;
			_root.map.ways[w].version=result[3];
			_root.map.ways[w].uid=result[4];
			_root.map.ways[w].removeNodeIndex();
			_root.map.ways[w].path=[];
			_root.map.ways[w].resetBBox();
			for (i=0; i<result[1].length; i++) {
				x =result[1][i][0];
				y =result[1][i][1];
				id=result[1][i][2];
				_root.map.ways[w].updateBBox(x,y);
				x=long2coord(x); y=lat2coord(y);
				if (nodes[id]) {
					// already exists: move node in other ways if required
					// ** maybe we should take out 'w'? not sure
					if (_root.map.ways[w].checkconnections) { nodes[id].moveTo(x,y,w); }
				} else {
					// doesn't exist, so create new node
					_root.nodes[id]=new Node(id,x,y,result[1][i][3],result[1][i][4]);
					_root.nodes[id].clean=true;
					if (id==prenode) { prepoint=i; }
				}
				_root.map.ways[w].path.push(_root.nodes[id]);
				_root.nodes[id].addWay(w);
				if (_root.nodes[id].ways[_root.wayselected] && w!=_root.wayselected) { redrawws=true; }
				else if (_root.nodes[id].isDupe()) {
					l=_root.pos[x+","+y]; for (b in l) {
						n=_root.pos[x+","+y][b];
						if (n.id!=id && n.ways[wayselected]) { redrawws=true; }
					}
				}
			}
			_root.map.ways[w].attr=result[2];
			_root.map.ways[w].redraw();
			if (redrawws)  { _root.ws.highlightPoints(5000,"anchor"); }	// need to redraw [_]s if new connections loaded
			if (w==preway) { _root.map.ways[w].select(); preway=undefined; }
			if (prepoint)  { _root.map.ways[w].select(); 
							 _root.map.anchors[prepoint].select();
							 prenode=prepoint=undefined; }
			_root.map.ways[w].clearPOIs();
			_root.map.ways[w].checkconnections=false;
		};
		remote_read.call('getway',responder,Math.floor(this._name));
	};

	OSMWay.prototype.loadFromDeleted=function(timestamp) {
		delresponder=function() { };
		delresponder.onResult=function(result) {
			var code=result.shift(); var msg=result.shift(); if (code) { handleError(code,msg,result); return; }
			var i,id,n;
			var w=_root.map.ways[result[0]];
			var oldpath=new Object();		// make sure to delete any nodes not in reverted way
			for (i=0; i<w.path.length; i++) { oldpath[w.path[i].id]=w.path[i].version; }
			if (result[4]) { w.historic=false; w.clean=true;  }
			          else { w.historic=true;  w.clean=false; }
			w.version=result[3];
			w.removeNodeIndex();
			w.path=[];
			w.resetBBox();
			for (i=0; i<result[1].length; i++) {
				n=result[1][i];
				x=n[0]; y=n[1]; id=n[2];					// 3:current version, 4:tags, 5:reuse?
				if (id<0) { id=--_root.newnodeid; }			// assign negative IDs to anything moved
				delete oldpath[id];
				w.updateBBox(x,y);
				x=long2coord(x); y=lat2coord(y);
				if (nodes[id]) {
					if (x!=nodes[id].x || y!=nodes[id].y) {
						// ** also needs to check that tags haven't changed
						nodes[id].moveTo(x,y,w);
						nodes[id].attr=n[4];
						nodes[id].version=n[3];
						w.clean=false;
					}
					if (n[5]) { nodes[id].clean=true; }		// is visible and current version
				} else {
					_root.nodes[id]=new Node(id,x,y,n[4],n[3]);
				}
				w.path.push(_root.nodes[id]);
				_root.nodes[id].addWay(result[0]);
			}
			for (i in oldpath) { if (i>0) { w.deletednodes[i]=oldpath[i]; } }
			w.attr=result[2];
			if (w==ws) { w.select(); }
				  else { w.locked=true; }
			w.redraw();
			w.clearPOIs();
		};
		remote_read.call('getway_old',delresponder,Number(this._name),timestamp);
	};

	OSMWay.prototype.clearPOIs=function() {
		// check if any way nodes are POIs, delete the POIs if so
		var i,z;
		z=this.path;
		for (i in z) {
			if (_root.map.pois[this.path[i].id]) { removeMovieClip(_root.map.pois[this.path[i].id]); }
		}
	};

	// ----	Draw line

	OSMWay.prototype.redraw=function(skip,skiponeway) {
		this.createEmptyMovieClip("taggednodes",3);

		if (skip && !this.attr["oneway"]) {
			// We're at the same scale as previously, so don't redraw
			// ** will refactor this when we do proper POI icons
			for (var i=0; i<this.path.length; i+=1) {
				if (this.path[i].tagged) {
					this.taggednodes.attachMovie("poiinway",i,i);
					this.taggednodes[i]._x=this.path[i].x;
					this.taggednodes[i]._y=this.path[i].y;
					this.taggednodes[i]._xscale=this.taggednodes[i]._yscale=taggedscale;
				}
			}
		} else {

			// Either the line has changed, or we've changed scale
			this.createEmptyMovieClip("line",1);					// clear line
			this.createEmptyMovieClip("arrows",2);					//  |
			var linealpha=100; // -50*(this.locked==true);
			var casingx=(scale<17 || preferences.data.thinlines) ? 1.5 : 1.3; var casingcol=0x222222;
	
			// Set stroke
	
			var f=this.getFill();
			if		(this.locked)					 { this.line.lineStyle(linewidth,0xFF0000,linealpha,false,"none"); }
			else if (colours[this.attr["highway"]])  { this.line.lineStyle(linewidth,colours[this.attr["highway" ]],linealpha,false,"none"); }
			else if (colours[this.attr["waterway"]]) { this.line.lineStyle(linewidth,colours[this.attr["waterway"]],linealpha,false,"none"); }
			else if (colours[this.attr["railway"]])  { this.line.lineStyle(linewidth,colours[this.attr["railway" ]],linealpha,false,"none"); }
			else {
				var c=0xAAAAAA; var z=this.attr;
				for (var i in z) { if (i!='created_by' && this.attr[i]!='' && this.attr[i].substr(0,6)!='(type ') { c=0x707070; } }
				this.line.lineStyle((f>-1 || this.attr['boundary']) ? areawidth : linewidth,c,linealpha,false,"none");
			}
			
			// Draw fill/casing
	
			var br=false;
			if (preferences.data.tiger && this.uid==7168 && this.version==1 && this.clean && this.attr["tiger:tlid"]) {
                casingx=2; casingcol=0xFF00FF;
			} else if (preferences.data.noname && this.attr["highway"] && (!this.attr["name"] || this.attr["name"].substr(0,6)=='(type ')) {
                casingx=2; casingcol=0xFF0000;
			} else if (this.attr["bridge"] && this.attr["bridge"]!="no") {
				casingx=(scale<17) ? 2 : 1.8; br=true;
			}

			if ((f>-1 || br || casing[this.attr['highway']]) && !this.locked) {
				if (!_root.map.areas[this._name]) { _root.map.areas.createEmptyMovieClip(this._name,++areadepth); }
				with (_root.map.areas[this._name]) {
					clear();
					enabled=false;
					moveTo(this.path[0].x,this.path[0].y); 
					if (f>-1) { beginFill(f,20); }
						 else { lineStyle(linewidth*casingx,casingcol,100,false,"none"); }
					for (var i=1; i<this.path.length; i+=1) {
						lineTo(this.path[i].x,this.path[i].y);
					}
					if (f>-1) { endFill(); }
				};
			} else if (_root.map.areas[this._name]) {
				removeMovieClip(_root.map.areas[this._name]);
			}
	
			// Draw line and tagged nodes
	
			this.line.moveTo(this.path[0].x,this.path[0].y);
			for (var i=0; i<this.path.length; i+=1) {
				if (i>0) { this.line.lineTo(this.path[i].x,this.path[i].y); }
				if (this.path[i].tagged) {
					// **** attach correct icon:
					// if (this.path[i].attr['frog']) {
					// this.taggednodes.attachMovie("poi_22",i,i); 
					// ...probably don't have to do _root.map.pois[point].__proto__=undefined;
					//    because clicks are handled by the way movieclip
					this.taggednodes.attachMovie("poiinway",i,i);
					this.taggednodes[i]._x=this.path[i].x;
					this.taggednodes[i]._y=this.path[i].y;
					this.taggednodes[i]._xscale=this.taggednodes[i]._yscale=taggedscale;
				}
			}

			// Draw relations

			var z=_root.wayrels[this._name];
			for (var rel in z) { _root.map.relations[rel].redraw(); }
			
			// Draw direction arrows
			
			if (this.attr["oneway"] && !skiponeway) {
				this.drawArrows(this.attr["oneway"]);
			}
		}
	};

	OSMWay.prototype.getFill=function() {
		var f=-1; 
		if (this.path[this.path.length-1]==this.path[0] && this.path.length>2) {
			if (this.attr['area']) { f='0x777777'; }
			var z=this.attr;
			for (var i in z) { if (areas[i] && this.attr[i]!='' && this.attr[i]!='coastline') { f=areas[i]; } }
		}
		return f;
	};

	OSMWay.prototype.drawArrows=function(dir) {
		if (dir=='no' || dir=='false') { return; }
		var dashes=[4,1,1,1,1,10];
		var widths=[2,7,5,3,1,0];
		if (dir=="-1") { dashes.reverse(); widths.reverse(); }
		var arrowcol=0x6C70D5; if (this.attr['highway']=='primary' || this.attr['highway']=='primary_link' || 
								   this.attr['highway']=='trunk' || this.attr['highway']=='trunk_link' || 
								   this.attr['highway']=='motorway' || this.attr['highway']=='motorway_link') { arrowcol=0; }
		
		var draw=false;
		var dashleft=0;
		var segleft=0;
		var dc=[]; var wc=[];
		var a,xc,yc,curx,cury,dx,dy;
		var i=0;

		var g=this.arrows;
		g.moveTo(this.path[0].x,this.path[0].y);
		while (i<this.path.length-1 || segleft>0) {
			if (dashleft<=0) {
				if (dc.length==0) { dc=dashes.slice(0); wc=widths.slice(0); }
				dashleft=dc.shift()/bscale*2;
				dashwidth=wc.shift();
			}
			if (segleft<=0) {
				curx=this.path[i].x; dx=this.path[i+1].x-curx;
				cury=this.path[i].y; dy=this.path[i+1].y-cury;
				a=Math.atan2(dy,dx); xc=Math.cos(a); yc=Math.sin(a);
				segleft=Math.sqrt(dx*dx+dy*dy);
				i++;
			}

			if (segleft<=dashleft) {
				// the path segment is shorter than the dash
	 			curx+=dx; cury+=dy;
				moveLine(g,curx,cury,dashwidth,arrowcol);
				dashleft-=segleft; segleft=0;
			} else {
				// the path segment is longer than the dash
				curx+=dashleft*xc; dx-=dashleft*xc;
				cury+=dashleft*yc; dy-=dashleft*yc;
				moveLine(g,curx,cury,dashwidth,arrowcol);
				segleft-=dashleft; dashleft=0;
			}
		}
	};

	function moveLine(g,x,y,dashwidth,colour) {
		if (dashwidth==0) {
			g.moveTo(x,y);
		} else {
			g.lineStyle(dashwidth,colour,100,false,"none","none");
			g.lineTo(x,y);
		}
	};

	// ----	Tidy in line/circle
	
	OSMWay.prototype.tidy=function() {
		var a=this.path[0]; var b=this.path[this.path.length-1];
		var w=new Object(); w[this._name]=true;
		if (a.id==b.id) {
			// Tidy in circle
			if (this.path.length<4) { return; }
			this.saveChangeUndo();
			
			// Find centre-point
			var patharea=0;
			var cx=0; var lx=b.x; //coord2long(b.x);
			var cy=0; var ly=b.y; //coord2y(b.y);
			for (var i=0; i<this.path.length; i++) {
                var latp=this.path[i].y; //coord2y(this.path[i].y);
                var lon =this.path[i].x; // coord2long(this.path[i].x);
				var sc = (lx*latp-lon*ly); //*masterscale;
				cx += (lx+lon)*sc;
				cy += (ly+latp)*sc;
				patharea += sc;
				lx=lon; ly=latp;
			}
			patharea/=2;
			cx=cx/patharea/6; //long2coord(cx/patharea/6);
			cy=cy/patharea/6; //y2coord(cy/patharea/6);

			// Average distance to centre
			var d=0; var angles=[];
			for (var i=0; i<this.path.length; i++) {
				d+=Math.sqrt(Math.pow(this.path[i].x-cx,2)+Math.pow(this.path[i].y-cy,2));
			}
			d=d/this.path.length;
			
			// Move each node
			for (var i=0; i<this.path.length-1; i++) {
				var c=Math.sqrt(Math.pow(this.path[i].x-cx,2)+Math.pow(this.path[i].y-cy,2));
				this.path[i].unsetPosition();
				this.path[i].x=cx+(this.path[i].x-cx)/c*d;
				this.path[i].y=cy+(this.path[i].y-cy)/c*d;
				this.path[i].setPosition();
				this.path[i].clean=false;
				var l=this.path[i].ways; for (var o in l) { w[o]=true; }
			}

			// Insert extra nodes to make circle
			// clockwise: angles decrease, wrapping round from -170 to 170
			var newpath=[]; var diff,b;
			var clockwise=_root.panel.i_clockwise._visible;
			for (var i=0; i<this.path.length-1; i++) {
				var j=(i+1) % this.path.length;
				newpath.push(this.path[i]);
				a1=Math.atan2(this.path[i].x-cx,this.path[i].y-cy)*(180/Math.PI);
				a2=Math.atan2(this.path[j].x-cx,this.path[j].y-cy)*(180/Math.PI);

				if (clockwise) {
					if (a2>a1) { a2=a2-360; }
					diff=a1-a2;
					if (diff>20) {
						for (var ang=a1-20; ang>a2+10; ang-=20) {
							_root.newnodeid--;
							_root.nodes[newnodeid]=new Node(newnodeid,cx+Math.sin(ang*Math.PI/180)*d,cy+Math.cos(ang*Math.PI/180)*d,new Object(),0);
							_root.nodes[newnodeid].addWay(this._name);
							newpath.push(_root.nodes[newnodeid]);
						}
					}
				} else {
					if (a1>a2) { a1=a1-360; }
					diff=a2-a1;
					if (diff>20) {
						for (var ang=a1+20; ang<a2-10; ang+=20) {
							_root.newnodeid--;
							_root.nodes[newnodeid]=new Node(newnodeid,cx+Math.sin(ang*Math.PI/180)*d,cy+Math.cos(ang*Math.PI/180)*d,new Object(),0);
							_root.nodes[newnodeid].addWay(this._name);
							newpath.push(_root.nodes[newnodeid]);
						}
					}
				}
			}
			newpath.push(this.path[this.path.length-1]);
			this.path=newpath;

		} else {
			// Tidy in line
			if (this.path.length<3) { return; }

			// First, calculate divergence to make sure we're not straightening a really bendy way
			var d=0; var t,x1,y1;
			var thislat=coord2lat(_root.map._y); var latfactor=Math.cos(thislat/(180/Math.PI));
			for (var i=1; i<this.path.length-1; i++) {
				u=((this.path[i].x-a.x)*(b.x-a.x)+
				   (this.path[i].y-a.y)*(b.y-a.y))/
				   (Math.pow(b.x-a.x,2)+Math.pow(b.y-a.y,2));
				x1=a.x+u*(b.x-a.x);
				y1=a.y+u*(b.y-a.y);
				t=Math.sqrt(Math.pow(x1-this.path[i].x,2)+Math.pow(y1-this.path[i].y,2));
				t=Math.floor((111200*latfactor)*t/masterscale);
				if (t>d) { d=t; }
			}
			if (d>50 && !Key.isDown(Key.SHIFT)) { setAdvice(false,iText('advice_bendy')); return; }
			this.saveChangeUndo();

			var el=long2coord(_root.bigedge_l);		// We don't want to delete any off-screen nodes
			var er=long2coord(_root.bigedge_r);		// (because they might be used in other ways)
			var et= lat2coord(_root.bigedge_t);
			var eb= lat2coord(_root.bigedge_b);
			var retain=new Array(a);
			for (var i=1; i<this.path.length-1; i++) {
				if (this.path[i].numberOfWays()>1 || hasTags(this.path[i].attr) ||
					this.path[i].x<el || this.path[i].x>er || 
					this.path[i].y<et || this.path[i].y>eb) {
					u=((this.path[i].x-a.x)*(b.x-a.x)+
					   (this.path[i].y-a.y)*(b.y-a.y))/
					   (Math.pow(b.x-a.x,2)+Math.pow(b.y-a.y,2));
					this.path[i].unsetPosition();
					this.path[i].x=a.x+u*(b.x-a.x);
					this.path[i].y=a.y+u*(b.y-a.y);
					this.path[i].setPosition();
					this.path[i].clean=false;
					var l=this.path[i].ways; for (var o in l) { w[o]=true; }
					retain.push(this.path[i]);
				} else {
					this.markAsDeleted(this.path[i],false);
					this.path[i].unsetPosition();
					memberDeleted('Node', this.path[i].id);
				}
			}
			retain.push(b);
			this.path=retain;
			this.removeDuplicates();
		}
		this.clean=false; markClean(false);
		for (var i in w) { _root.map.ways[i].redraw(); }
		this.select();
	};



	// ----	Show direction

	OSMWay.prototype.direction=function() {
		if (this.path.length<2) {
			_root.panel.i_clockwise._visible=false;
			_root.panel.i_anticlockwise._visible=false;
			_root.panel.i_direction._visible=true;
			_root.panel.i_direction._alpha=50;
		} else {
			var dx=this.path[this.path.length-1].x-this.path[0].x;
			var dy=this.path[this.path.length-1].y-this.path[0].y;
			if (dx!=0 || dy!=0) {
				// Non-circular
				_root.panel.i_direction._rotation=180-Math.atan2(dx,dy)*(180/Math.PI)-45;
				_root.panel.i_direction._alpha=100;
				_root.panel.i_direction._visible=true;
				_root.panel.i_clockwise._visible=false;
				_root.panel.i_anticlockwise._visible=false;
			} else {
				// Circular
				_root.panel.i_direction._visible=false;
				// Find lowest rightmost point
				// cf http://geometryalgorithms.com/Archive/algorithm_0101/
				var lowest=0;
				var xmax=-999999; var ymin=-999999;
				for (var i=0; i<this.path.length; i++) {
					if      (this.path[i].y> ymin) { lowest=i; xmin=this.path[i].x; ymin=this.path[i].y; }
					else if (this.path[i].y==ymin
						  && this.path[i].x> xmax) { lowest=i; xmin=this.path[i].x; ymin=this.path[i].y; }
				}
				var clockwise=(this.onLeft(lowest)>0);
				_root.panel.i_clockwise._visible=clockwise;
				_root.panel.i_anticlockwise._visible=!clockwise;
			}
		}
	};

	OSMWay.prototype.onLeft=function(j) {
		var left=0;
		if (this.path.length>=3) {
			var i=j-1; if (i==-1) { i=this.path.length-2; }
			var k=j+1; if (k==this.path.length) { k=1; }
			left=((this.path[j].x-this.path[i].x) * (this.path[k].y-this.path[i].y) -
				  (this.path[k].x-this.path[i].x) * (this.path[j].y-this.path[i].y));
		}
		return left;
	};
	


	// ----	Remove from server
	
	OSMWay.prototype.remove=function() {
		clearFloater();
		memberDeleted('Way', this._name);
		var z=this.path; for (var i in z) {
			if (z[i].numberOfWays()==1) { z[i].unsetPosition(); memberDeleted('Node', z[i].id); }
		}
		uploadDirtyRelations();

		this.deleteMergedWays();
		this.removeNodeIndex();

		if (!this.historic && !this.locked) {
			var z=shallowCopy(this.path); this.path=new Array();
			for (var i in z) { this.markAsDeleted(z[i],false); }
			if (_root.sandbox) {
				if (this._name>=0) { 
					_root.waystodelete[this._name]=[this.version,deepCopy(this.deletednodes)];
				} else {
					var z=this.deletednodes; for (var j in z) { deleteNodeAsPOI(j); }
					var z=this.path;         for (var j in z) { deleteNodeAsPOI(j.id); }
					markClean(false);
				}
			} else if (this._name>=0) {
				if (renewChangeset()) { return; }
				deleteresponder = function() { };
				deleteresponder.onResult = function(result) { deletewayRespond(result); };
				_root.writesrequested++;
				remote_write.call('deleteway',deleteresponder,_root.usertoken,_root.changeset,Number(this._name),Number(this.version),this.deletednodes);
			}
		}

		if (this._name==wayselected) { stopDrawing(); deselectAll(); }
		removeMovieClip(_root.map.areas[this._name]);
		removeMovieClip(this);
	};

	function deletewayRespond(result) {
		_root.writesrequested--;
		var code=result.shift(); var msg=result.shift(); if (code) { handleError(code,msg,result); return; }
		var z=result[2]; for (var i in z) { delete _root.nodes[i]; }
		operationDone(result[0]);
		freshenChangeset();
	};

	function deleteNodeAsPOI(nid) {
		if (nid<0) { return; }
		if (_root.nodes[nid].numberOfWays()>0) { return; }
		// if we're not going to send a deleteway for this (because it's negative - probably due to a split),
		// then delete it as a POI instead
		var n=_root.nodes[nid];
		_root.poistodelete[nid]=[n.version,coord2long(n.x),coord2lat(n.y),deepCopy(n.attr)];
	}

	// ---- Variant with confirmation if any nodes have tags
	
	OSMWay.prototype.removeWithConfirm=function() {
		var c=true;
		var z=this.path;
		for (var i in z) {
			if ((this.path[i].tagged && hashLength(this.path[i].ways)==1) || hashLength(noderels[this.path[i].id])) { c=false; }
		}
		if (c) {
			_root.ws.saveDeleteUndo(iText('deleting'));
			this.remove();
			markClean(true);
		} else {
			_root.windows.attachMovie("modal","confirm",++windowdepth);
			_root.windows.confirm.init(275,80,new Array(iText('cancel'),iText('delete')),
				function(choice) {
					if (choice==iText('delete')) { _root.ws.saveDeleteUndo(iText('deleting')); _root.ws.remove(); markClean(true); }
				});
			_root.windows.confirm.box.createTextField("prompt",2,7,9,250,100);
			writeText(_root.windows.confirm.box.prompt,iText('prompt_taggedpoints'));
		}
	};

	// ----	Upload to server
	
	OSMWay.prototype.upload=function() {
		putresponder=function() { };
		putresponder.onResult=function(result) {
			_root.writesrequested--;
			var code=result.shift(); var msg=result.shift(); if (code) { _root.map.ways[result[0]].notUploading(); handleError(code,msg,result); return; }

			var i,r,z,nw,ow;
			ow=result[0];			// old way ID
			nw=result[1];			// new way ID
			if (ow!=nw) { renumberWay(ow,nw); }
			_root.map.ways[nw].clean=true;
			_root.map.ways[nw].uploading=false;
			_root.map.ways[nw].historic=false;
			_root.map.ways[nw].version=result[3];
			
			// renumber nodes (and any relations/ways they're in)
			z=result[2];
			for (var oid in z) {
				var nid = result[2][oid];
				nodes[oid].renumberTo(nid);
				nodes[nid].addWay(nw);
				renumberMemberOfRelation('Node', oid, nid);
			}
			for (var oid in z) { delete _root.nodes[oid]; }	// delete -ve nodes
			
			// set versions, clean, not uploading
			z=result[4]; for (var nid in z) { nodes[nid].version=result[4][nid]; nodes[nid].uploading=false; nodes[nid].clean=true; }

			// remove deleted nodes
			z=result[5]; for (var nid in z) { c=_root.map.ways[nw]; delete c.deletednodes[nid]; delete _root.nodes[nid]; }
			
			_root.map.ways[nw].clearPOIs();
			uploadDirtyRelations();
			_root.map.ways[nw].deleteMergedWays();
			uploadDirtyWays();			// make sure dependencies are uploaded
			operationDone(ow);
			freshenChangeset();
			updateInspector();
		};

		if (!this.uploading && !this.hasDependentNodes() && !this.locked && (!_root.sandbox || _root.uploading) && this.path.length>1) {
			this.deleteMergedWays();

			// Assemble list of changed nodes, and send
			if (renewChangeset()) { return; }
			this.uploading=true;
			var sendpath =new Array();
			var sendnodes=new Array();
			for (i=0; i<this.path.length; i++) {
				sendpath.push(this.path[i].id);
				if (!this.path[i].clean && !this.path[i].uploading) {
					sendnodes.push(new Array(coord2long(this.path[i].x),
											 coord2lat (this.path[i].y),
											 this.path[i].id,this.path[i].version,
											 deepCopy  (this.path[i].attr)));
					this.path[i].uploading=true;
				}
			}
			delete this.attr['created_by'];
			_root.writesrequested++;
			remote_write.call('putway',putresponder,_root.usertoken,_root.changeset,this.version,Number(this._name),sendpath,this.attr,sendnodes,this.deletednodes);
			updateInspector();
		} else { 
			operationDone(this._name);	// next please!
		}
	};

	// ---- Delete any ways merged into this one

	OSMWay.prototype.deleteMergedWays=function() {
		while (this.mergedways.length>0) {
			var i=this.mergedways.shift();
			_root.map.ways.attachMovie("way",i[0],++waydepth);	// can't remove unless the movieclip exists!
			_root.map.ways[i[0]].version=i[1];					//  |
			_root.map.ways[i[0]].deletednodes=i[2];				//  |
			_root.map.ways[i[0]].remove();
		}
	};

	// ----	Revert to copy in database
	
	OSMWay.prototype.reload=function() {
		_root.waysrequested+=1;
		while (this.mergedways.length>0) {
			var i=this.mergedways.shift();
			_root.waysrequested+=1;
			_root.map.ways.attachMovie("way",i[0],++waydepth);
			_root.map.ways[i[0]].load();
		}
		this.checkconnections=true;
		this.load();
	};
	
	// ----	Save for undo

	OSMWay.prototype.saveDeleteUndo=function(str) {
		_root.undo.append(UndoStack.prototype.undo_deleteway,
						  new Array(this._name,this._x,this._y,
									deepCopy(this.attr),deepCopy(this.path),this.version),
									iText('a_way',str));
	};
	
	OSMWay.prototype.saveChangeUndo=function(str) {
		_root.undo.append(UndoStack.prototype.undo_changeway,
						  new Array(this._name,deepCopy(this.path),deepCopy(this.deletednodes),deepCopy(this.attr)),
						  iText('action_changeway'));
	};


	// ----	Click handling	

	OSMWay.prototype.onRollOver=function() {
		if (this._name!=_root.wayselected && _root.drawpoint>-1 && !_root.map.anchorhints) {
			this.highlightPoints(5001,"anchorhint");
			setPointer('penplus');
		} else if (_root.drawpoint>-1) { setPointer('penplus'); }
								  else { setPointer(''); }
		if (this._name!=_root.wayselected) { var a=getName(this.attr,waynames); if (a) { setFloater(a); } }
	};
	
	OSMWay.prototype.onRollOut=function() {
		if (this.hitTest(_root._xmouse,_root._ymouse,true)) { return; }	// false rollout
		if (_root.wayselected) { setPointer(''   ); }
						  else { setPointer('pen'); }
		_root.map.anchorhints.removeMovieClip();
		clearFloater();
	};
	
	OSMWay.prototype.onPress=function() {
		removeWelcome(true);
		if (Key.isDown(Key.SHIFT) && this._name==_root.wayselected && _root.drawpoint==-1) {
			// shift-click current way: insert point
			this.insertAnchorPointAtMouse();
		} else if (Key.isDown(Key.SHIFT) && _root.wayselected && this.name!=_root.wayselected && _root.drawpoint==-1 && _root.ws.hitTest(_root._xmouse,_root._ymouse,true)) {
			// shift-click other way (at intersection with current): make intersection
			this.insertAnchorPointAtMouse();
		} else if (Key.isDown(Key.CONTROL) && _root.wayselected && this.name!=_root.wayselected && _root.drawpoint==-1) {
			// control/command-click other way: merge two ways
			mergeWayKeepingID(this,_root.ws);
		} else if (_root.drawpoint>-1) {
			// click other way while drawing: insert point as junction
			if (!this.historic) {
				if (this._name==_root.wayselected && _root.drawpoint>0) {
					_root.drawpoint+=1;	// inserting node earlier into the way currently being drawn
				}
				_root.newnodeid--;
				_root.nodes[newnodeid]=new Node(newnodeid,0,0,new Object(),0);
				this.insertAnchorPoint(_root.nodes[newnodeid]);
				this.highlightPoints(5001,"anchorhint");
				addEndPoint(_root.nodes[newnodeid]);
			}
			_root.junction=true;
			restartElastic();
		} else {
			// click way: select
			_root.panel.properties.saveAttributes();
			this.select();
			clearTooltip();
			_root.clicktime=new Date();
			// was the click on a tagged node? if so, select directly
			var n;
			for (var i=0; i<this.path.length; i+=1) {
				if (this.taggednodes[i].hitTest(_root._xmouse,_root._ymouse,true)) { n=i; }
			}
			if (n) { _root.map.anchors[n].beginDrag();
					 _root.map.anchors[n].select(); }
			  else { this.beginDrag(); }
		}
	};

	OSMWay.prototype.beginDrag=function() {
		this.onMouseMove=function() { this.trackDrag(); };
		this.onMouseUp  =function() { this.endDrag();   };
		this.dragged=false;
		this.held=true;
		_root.firstxmouse=_root.map._xmouse;
		_root.firstymouse=_root.map._ymouse;
	};

	OSMWay.prototype.trackDrag=function() {
		var t=new Date();
		var longclick=(t.getTime()-_root.clicktime)>1000;
		var xdist=Math.abs(_root.map._xmouse-_root.firstxmouse);
		var ydist=Math.abs(_root.map._ymouse-_root.firstymouse);
		// Don't enable drag unless way held for a while after click
		if ((xdist>=tolerance   || ydist>=tolerance  ) &&
			(t.getTime()-_root.clicktime)<300 &&
			lastwayselected!=wayselected) { this.held=false; }
		// Move way if dragged a long way, or dragged a short way after a while
		if ((xdist>=tolerance*4 || ydist>=tolerance*4) ||
		   ((xdist>=tolerance/4 || ydist>=tolerance/4) && longclick) &&
		   this.held) {
			this.dragged=true;
		}
		if (this.dragged) {
			_root.map.anchors._x=_root.map.areas[this._name]._x=_root.map.highlight._x=this._x=_root.map._xmouse-_root.firstxmouse;
			_root.map.anchors._y=_root.map.areas[this._name]._y=_root.map.highlight._y=this._y=_root.map._ymouse-_root.firstymouse;
		}
	};
	
	OSMWay.prototype.endDrag=function() {
		delete this.onMouseMove;
		delete this.onMouseUp;
		_root.map.anchors._x=_root.map.areas[this._name]._x=_root.map.highlight._x=this._x=0;
		_root.map.anchors._y=_root.map.areas[this._name]._y=_root.map.highlight._y=this._y=0;
		if (this.dragged) {
			this.moveNodes(_root.map._xmouse-_root.firstxmouse,_root.map._ymouse-_root.firstymouse);
			setAdvice(false,iText('advice_waydragged'));
			this.redraw();
			this.select();
			_root.undo.append(UndoStack.prototype.undo_movenodes,
							  new Array(this,_root.map._xmouse-_root.firstxmouse,
								  			 _root.map._ymouse-_root.firstymouse),
							  iText('action_moveway'));
		}
	};
	
	// ----	Select/highlight
	
	OSMWay.prototype.select=function() {
		_root.panel.properties.tidy();
		if (_root.wayselected!=this._name || _root.poiselected!=0) { uploadSelected(); }
//		_root.panel.properties.saveAttributes();
		_root.pointselected=-2;
		selectWay(this._name);
		_root.poiselected=0;
		this.highlightPoints(5000,"anchor");
		removeMovieClip(_root.map.anchorhints);
		this.highlight();
		setTypeText(iText('way'),this._name);
		removeIconPanel();
		_root.panel.properties.init('way',getPanelColumns(),4);
		_root.panel.presets.init(_root.panel.properties);
		updateButtons();
		updateScissors(false);
	};
	
	OSMWay.prototype.highlight=function() {
		_root.map.createEmptyMovieClip("highlight",5);
		if (_root.pointselected>-2) {
			highlightSquare(_root.map.anchors[pointselected]._x,_root.map.anchors[pointselected]._y, _root.anchorsize*0.05);
		} else {
			var linecolour=0xFFFF00; if (this.locked) { var linecolour=0x00FFFF; }
			_root.map.highlight.lineStyle(linewidth*1.5+8,linecolour,80,false,"none");
			_root.map.highlight.moveTo(this.path[0].x,this.path[0].y);
			for (var i=1; i<this.path.length; i+=1) {
				_root.map.highlight.lineTo(this.path[i].x,this.path[i].y);
			}
		}
		this.direction();
	};

	OSMWay.prototype.highlightPoints=function(d,atype) {
		var group=atype+"s";
		_root.map.createEmptyMovieClip(group,d);
		for (var i=0; i<this.path.length; i+=1) {
			var asprite=atype; 
			if (this.path[i].isDupe()) { asprite+="_dupe"; }
			else if (this.path[i].numberOfWays()>1) { asprite+="_junction"; }
			_root.map[group].attachMovie(asprite,i,i);
			_root.map[group][i]._x=this.path[i].x;
			_root.map[group][i]._y=this.path[i].y;
			_root.map[group][i]._xscale=_root.anchorsize;
			_root.map[group][i]._yscale=_root.anchorsize;
			_root.map[group][i].node=this.path[i].id;
			_root.map[group][i].way=this;
			if (this.path[i].tagged) {
				// anchor point should be black if it has tags
				_root.map[group][i].blacken=new Color(_root.map[group][i]);
				_root.map[group][i].blacken.setTransform(to_black);
			}
		}
	};

	// ----	Split, merge, reverse

	OSMWay.prototype.splitWay=function(point,newattr) {
		var i,z;
		if (point>0 && point<(this.path.length-1) && !this.historic) {
			_root.newwayid--;											// create new way
			_root.map.ways.attachMovie("way",newwayid,++waydepth);		//  |
			_root.map.ways[newwayid].path=shallowCopy(this.path);		// deep copy path array
			this.removeNodeIndex();

			if (newattr) { _root.map.ways[newwayid].attr=newattr; }
					else { _root.map.ways[newwayid].attr=deepCopy(this.attr); }

			z=_root.wayrels[this._name];								// copy relations
			for (i in z) {												//  | 
				_root.map.relations[i].setWayRole(newwayid,z[i]);		//  |
			}															//  |
 
			this.path.splice(Math.floor(point)+1);						// current way
			this.redraw();												//  |
			this.createNodeIndex();

			_root.map.ways[newwayid].path.splice(0,point);				// new way
			_root.map.ways[newwayid].locked=this.locked;				//  |
			_root.map.ways[newwayid].redraw();							//  |
			_root.map.ways[newwayid].clean=false;						//  | - in case it doesn't upload
			_root.map.ways[newwayid].upload();							//  |
			_root.map.ways[newwayid].createNodeIndex();					//  |

			this.clean=false;											// upload current way
			this.upload();												//  |
			this.select();												//  |
			uploadDirtyRelations();
			_root.undo.append(UndoStack.prototype.undo_splitway,
							  new Array(this,_root.map.ways[newwayid]),
							  iText('action_splitway'));
		};
	};

	//		Merge (start/end of this way,other way object,start/end of other way)

	OSMWay.prototype.mergeWay=function(topos,otherway,frompos) {
		var i,z;
		var conflict=false;
		if (this.historic || otherway.historic) { return; }
		if (otherway==this) { return; }

		var mergepoint=this.path.length;
		if (topos==0) {
			_root.undo.append(UndoStack.prototype.undo_mergeways,
							  new Array(this,deepCopy(otherway.attr),deepCopy(this.attr),frompos),
							  iText('action_mergeways'));
		} else {
			_root.undo.append(UndoStack.prototype.undo_mergeways,
							  new Array(this,deepCopy(this.attr),deepCopy(otherway.attr),topos),
							  iText('action_mergeways'));
		}
		if (frompos==0) { for (i=0; i<otherway.path.length;    i+=1) { this.addPointFrom(topos,otherway,i); } }
				   else { for (i=otherway.path.length-1; i>=0; i-=1) { this.addPointFrom(topos,otherway,i); } }

		// Merge attributes
		z=otherway.attr;
		for (i in z) {
			if (otherway.attr[i].substr(0,6)=='(type ') { otherway.attr[i]=null; }
			if (this.attr[i].substr(0,6)=='(type ') { this.attr[i]=null; }
			if (this.attr[i]) {
				if (this.attr[i]!=otherway.attr[i] && otherway.attr[i]) { var s=this.attr[i]+'; '+otherway.attr[i]; this.attr[i]=s.substr(0,255); conflict=true; }
			} else {
				this.attr[i]=otherway.attr[i];
			}
			if (!this.attr[i]) { delete this.attr[i]; }
		}

		// Merge relations
		z=_root.wayrels[otherway._name];						// copy relations
		for (i in z) {											//  | 
			if (!_root.wayrels[this._name][i]) {				//  |
				_root.map.relations[i].setWayRole(this._name,z[i]);	
			}													//  |
		}														//  |
		memberDeleted('Way', otherway._name);					// then remove old way from them
		z=otherway.deletednodes;								//  | and its deletednodes
		for (i in z) { memberDeleted('Node',z[i]); }			//  |

		// Add to list of merged ways (so they can be deleted on next putway)
        if (_root.sandbox) {
            otherway.remove();
        } else {
    		this.mergedways.push(new Array(otherway._name,otherway.version,otherway.deletednodes));
    		this.mergedways.concat(otherway.mergedways);
    	}
		this.clean=false;
		markClean(false);
		if (otherway.locked) { this.locked=true; }
		otherway.removeNodeIndex();
		removeMovieClip(_root.map.areas[otherway._name]);
		removeMovieClip(otherway);
		if (this._name==_root.wayselected) { 
			_root.panel.properties.reinit();
		}
		if (conflict) { setAdvice(false,iText('advice_tagconflict')); }
	};

	OSMWay.prototype.addPointFrom=function(topos,otherway,srcpt) {
		if (topos==0) { if (this.path[0					]==otherway.path[srcpt]) { return; } }	// don't add duplicate points
				 else { if (this.path[this.path.length-1]==otherway.path[srcpt]) { return; } }	//  |
		if (topos==0) { this.path.unshift(otherway.path[srcpt]); }
			     else { this.path.push(otherway.path[srcpt]); }
		otherway.path[srcpt].addWay(this._name);
	};

	OSMWay.prototype.mergeAtCommonPoint=function(sel) {
		var selstart =sel.path[0];
		var sellen   =sel.path.length-1;
		var selend   =sel.path[sellen];
		var thisstart=this.path[0];
		var thislen  =this.path.length-1;
		var thisend  =this.path[thislen];
		if      (selstart==thisstart) { sel.mergeWay(0,this,0);			   return true; }
		else if (selstart==thisend  ) { sel.mergeWay(0,this,thislen);	   return true; }
		else if (selend  ==thisstart) { sel.mergeWay(sellen,this,0);	   return true; }
		else if (selend  ==thisend  ) { sel.mergeWay(sellen,this,thislen); return true; }
		else						  { setAdvice(true,iText('advice_nocommonpoint')); return false; }
	};

	// ---- Reverse order
	
	OSMWay.prototype.reverseWay=function() {
		if (this.path.length<2) { return; }
		if (_root.drawpoint>-1) { _root.drawpoint=(this.path.length-1)-_root.drawpoint; }
		this.path.reverse();
		this.redraw();
		this.direction();
		this.select();
		this.clean=false;
		markClean(false);
		_root.undo.append(UndoStack.prototype.undo_reverse,new Array(this),iText('action_reverseway'));
	};

	// ----	Remove dupe nodes
	
	OSMWay.prototype.joinNodes=function() {
		for (var i=0; i<this.path.length; i++) {
			if (this.path[i].isDupe()) {
				this.path[i].removeDupes([]);
			}
		}
		this.redraw();
		this.select();
		this.clean=false;
		markClean(false);
	};
	
	// ----	Move all nodes within a way
	
	OSMWay.prototype.moveNodes=function(xdiff,ydiff) {
		var i,n;
		var movedalready=new Array();
		this.clean=false;
		markClean(false);
		for (i=0; i<this.path.length; i+=1) {
			n=this.path[i].id;
			if (movedalready[n]) {
			} else {
				this.path[i].moveTo(this.path[i].x+xdiff,
									this.path[i].y+ydiff,
									this._name);
				movedalready[n]=true;
			}
		}
	};

	// ----	Add node to deleted list
	//		(should have been removed from way first)
	
	OSMWay.prototype.markAsDeleted=function(rnode,check2) {
		var d=true;
		// If we're just removing one point, check it's not used elsewhere in the way before removing from .ways
		if (check2) {
			var z=this.path; 
			for (var i in z) { if (this.path[i].id==rnode.id) { d=false; } }
		}
		if (d) { rnode.removeWay(this._name); }
		if (rnode.numberOfWays()==0 && rnode.id>0) { this.deletednodes[rnode.id]=rnode.version; }
	};


	// ----	Check for duplicates (e.g. when C is removed from ABCB)
	
	OSMWay.prototype.removeDuplicates=function() {
		var z=this.path; var ch=false;
		for (var i in z) {
			if (i>0) {
				if (this.path[i]==this.path[i-1]) { this.path.splice(i,1); ch=true; }
			}
		}
		return ch;
	};

	// ----	Add point into way with SHIFT-clicking
	//		cf http://local.wasp.uwa.edu.au/~pbourke/geometry/pointline/source.vba
	//		for algorithm to find nearest point on a line
	
	OSMWay.prototype.insertAnchorPoint=function(nodeobj) {
		var nx,ny,u,closest,closei,i,a,b,direct,via,newpoint;
		nx=_root.map._xmouse;	// where we're inserting it
		ny=_root.map._ymouse;	//	|
		closest=0.1; closei=0;
		for (i=0; i<(this.path.length)-1; i+=1) {
			a=this.path[i  ];
			b=this.path[i+1];
			direct=Math.sqrt((b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y));
			via   =Math.sqrt((nx -a.x)*(nx -a.x)+(ny -a.y)*(ny -a.y));
			via  +=Math.sqrt((nx -b.x)*(nx -b.x)+(ny -b.y)*(ny -b.y));
			if (Math.abs(via/direct-1)<closest) {
				closei=i+1;
				closest=Math.abs(via/direct-1);
				u=((nx-a.x)*(b.x-a.x)+
				   (ny-a.y)*(b.y-a.y))/
				   (Math.pow(b.x-a.x,2)+Math.pow(b.y-a.y,2));
				nodeobj.unsetPosition();
				nodeobj.x=a.x+u*(b.x-a.x);
				nodeobj.y=a.y+u*(b.y-a.y);
				nodeobj.setPosition();
			}
		}
		// Insert
		nodeobj.addWay(this._name);
		this.path.splice(closei,0,nodeobj);
		this.clean=false;
		this.redraw();
		markClean(false);
//		_root.adjustedxmouse=tx;	// in case we're adding extra points...
//		_root.adjustedymouse=ty;	// should probably return an array or an object **
		return closei;
	};

	//		Wrapper around the above to:
	//		- insert at mouse position
	//		- add to undo stack
	//		- add intersection at any crossing ways

	OSMWay.prototype.insertAnchorPointAtMouse=function() {
		_root.newnodeid--;
		_root.nodes[newnodeid]=new Node(newnodeid,0,0,new Object(),0);
		_root.pointselected=this.insertAnchorPoint(_root.nodes[newnodeid]);
		var waylist=new Array(); waylist.push(this);
		var poslist=new Array(); poslist.push(_root.pointselected);
		for (qway in _root.map.ways) {
			if (_root.map.ways[qway].hitTest(_root._xmouse,_root._ymouse,true) && qway!=this._name) {
				poslist.push(_root.map.ways[qway].insertAnchorPoint(_root.nodes[newnodeid]));
				waylist.push(_root.map.ways[qway]);
			}
		}
		_root.undo.append(UndoStack.prototype.undo_addpoint,
						  new Array(waylist,poslist), iText('action_insertnode'));
		_root.ws.highlightPoints(5000,"anchor");
		_root.map.anchors[pointselected].beginDrag();
		updateInspector();
	};

	// ----	Remove point from this way (only)
	
	OSMWay.prototype.removeAnchorPoint=function(point) {
		// ** if length<2, then mark as way removal
		_root.undo.append(UndoStack.prototype.undo_deletepoint,
						  new Array(deepCopy(this.path[point]),
						  			new Array(this._name),
						  			new Array(point)),
						  iText('action_deletepoint'));
		var rnode=this.path[point];
		this.path.splice(point,1);
		this.removeDuplicates();
		this.markAsDeleted(rnode,true);
		if (rnode.numberOfWays()==0) { memberDeleted('Node', rnode.id); rnode.unsetPosition(); }
		if (this.path.length<2) { this.remove(); }
						   else { this.redraw(); this.clean=false; }
	};

	// ----	Bounding box utility functions

	OSMWay.prototype.resetBBox=function() {
		this.xmin=this.ymin= 999;
		this.xmax=this.ymax=-999;
	};
	
	OSMWay.prototype.updateBBox=function(long,lat) {
		this.xmin=Math.min(long,this.xmin);
		this.xmax=Math.max(long,this.xmax);
		this.ymin=Math.min(lat ,this.ymin);
		this.ymax=Math.max(lat ,this.ymax);
	};

	// ----	Reset 'uploading' flag

	OSMWay.prototype.notUploading=function() {
		this.uploading=false;
		var z=this.path; for (i in z) { this.path[i].uploading=false; }
		updateInspector();
	};

	// ----	Node->way associations
	
	OSMWay.prototype.createNodeIndex  =function() { var z=this.path; for (var i in z) { this.path[i].addWay(this._name);    } };
	OSMWay.prototype.removeNodeIndex  =function() { var z=this.path; for (var i in z) { this.path[i].removeWay(this._name); } };
	OSMWay.prototype.renumberNodeIndex=function(n) {
		var z=this.path; for (i in z) { 
			this.path[i].removeWay(this._name);
			this.path[i].addWay(n);
		}
	};
	OSMWay.prototype.hasDependentNodes=function() {
        if (_root.sandbox && _root.uploading) { return false; }    // not an issue in consecutive uploads
		var d=false;
		var z=this.path; for (var i in z) {
			if (this.path[i].id<0) {
				var ways=this.path[i].ways; for (var w in ways) {
					if (_root.map.ways[w].uploading) { d=true; }
				}
			}
		}
		return d;
	};

	// =====================================================================================
	// Offset path
	// ** much of the dialogue box could be refactored to share with relations dialogue

	function askOffset() {
		if (!_root.wayselected) { return; }
		_root.windows.attachMovie("modal","offset",++windowdepth);
		_root.windows.offset.init(300, 170, [iText('cancel'), iText('ok')], completeOffset);
		var z = 5;
		var box = _root.windows.offset.box;
		
		box.createTextField("title",z++,7,7,300-14,20);
		box.title.text = iText('prompt_createparallel');
		with (box.title) {
			wordWrap=true;
			setTextFormat(boldText);
			selectable=false; type='dynamic';
		}
		adjustTextField(box.title);
		
		box.createTextField("instr",z++,7,30,300-14,40);

		// Create radio buttons and menu

		box.attachMovie("radio","offsetoption",z++);
		box.offsetoption.addButton(10,35 ,iText('offset_dual'));
		box.offsetoption.addButton(10,55 ,iText('offset_motorway'));
		box.offsetoption.addButton(10,75 ,iText('offset_narrowcanal'));
		box.offsetoption.addButton(10,95 ,iText('offset_broadcanal'));
		box.offsetoption.addButton(10,115,iText('offset_choose'));
		box.offsetoption.select(1);

		var w=box.offsetoption[5].prompt._width+25;
		box.createTextField("useroffset",z++,w,110,290-w,17);
		box.useroffset.setNewTextFormat(plainSmall);
		box.useroffset.type='input';
		box.useroffset.backgroundColor=0xDDDDDD;
		box.useroffset.background=true;
		box.useroffset.border=true;
		box.useroffset.borderColor=0xFFFFFF;
		box.useroffset.onSetFocus=function() { this._parent.offsetoption.select(5); };
	}

	// typical widths:
	// central reservation:
	//	 4.5m on a rural motorway/dual carriageway
	//	 3.5m on an urban motorway
	//	 1.8m on an urban dual carriageway
	// lane widths are typically always 3.65m
	// hard shoulders are typically 3.30m
	// hard strips are typically 1m 

	function completeOffset(button) {
		if (button!=iText('ok')) { return false; }
		var radio=_root.windows.offset.box.offsetoption.selected;
		var m;
		if (radio==5) {
			m=_root.windows.offset.box.useroffset.text;
			if (!button) { return false; }
		} else {
			m=new Array(0,4.5+3.65*2,4.5+3.65*3,5.5,11);
			m=m[radio];
		}
		var thislat=coord2lat(_root.map._y);			// near as dammit
		var latfactor=Math.cos(thislat/(180/Math.PI));	// 111200m in a degree at the equator
		m=masterscale/(111200*latfactor)*m;				// 111200m*cos(lat in radians) elsewhere
		_root.ws.offset( m);
		_root.ws.offset(-m);
		_root.undo.append(UndoStack.prototype.undo_makeways,
						  new Array(_root.newwayid,_root.newwayid+1),
						  iText('action_createparallel'));
	}

	// Create (locked) offset way
	// offset is + or - depending on which side

	OSMWay.prototype.offset=function(tpoffset) {
		var a,b,o,df,x,y;
		var offsetx=new Array();
		var offsety=new Array();
		var wm=1;	// was 10 before

		_root.newwayid--;											// create new way
		_root.map.ways.attachMovie("way",newwayid,++waydepth);		//  |
		var nw=_root.map.ways[newwayid];
		nw.locked=true;
		nw.clean=false;

		// Normalise, and calculate offset vectors

		for (var i=0; i<this.path.length; i++) {
			a=this.path[i  ].y - this.path[i+1].y;
			b=this.path[i+1].x - this.path[i  ].x;
			h=Math.sqrt(a*a+b*b);
			if (h!=0) { a=a/h; b=b/h; }
				 else {	a=0; b=0; }
			offsetx[i]=wm*a;
			offsety[i]=wm*b;
		}

		_root.newnodeid--;
		_root.nodes[newnodeid]=new Node(newnodeid,this.path[0].x+tpoffset*offsetx[0],
												  this.path[0].y+tpoffset*offsety[0],
												  new Object(),0);
		_root.nodes[newnodeid].addWay(newwayid);
		nw.path.push(_root.nodes[newnodeid]);
		
		for (i=1; i<(this.path.length-1); i++) {
	
			a=det(offsetx[i]-offsetx[i-1],
				  offsety[i]-offsety[i-1],
				  this.path[i+1].x - this.path[i  ].x,
				  this.path[i+1].y - this.path[i  ].y);
			b=det(this.path[i  ].x - this.path[i-1].x,
				  this.path[i  ].y - this.path[i-1].y,
				  this.path[i+1].x - this.path[i  ].x,
				  this.path[i+1].y - this.path[i  ].y);
			if (b!=0) { df=a/b; } else { df=0; }
			
			x=this.path[i].x + tpoffset*(offsetx[i-1]+df*(this.path[i].x - this.path[i-1].x));
			y=this.path[i].y + tpoffset*(offsety[i-1]+df*(this.path[i].y - this.path[i-1].y));
	
			_root.newnodeid--;
			_root.nodes[newnodeid]=new Node(newnodeid,x,y,new Object(),0);
			_root.nodes[newnodeid].addWay(newwayid);
			nw.path.push(_root.nodes[newnodeid]);
		}
	
		_root.newnodeid--;
		_root.nodes[newnodeid]=new Node(newnodeid,this.path[i].x+tpoffset*offsetx[i-1],
												  this.path[i].y+tpoffset*offsety[i-1],new Object(),0);
		_root.nodes[newnodeid].addWay(newwayid);
		nw.path.push(_root.nodes[newnodeid]);
		nw.redraw();
	};

    function det(a,b,c,d) { return a*d-b*c; }

	// =====================================================================================
	// Inspector
	
	OSMWay.prototype.inspect=function() {
		var str='';

		// Status
		if (this.locked) { str+=iText('inspector_way_locked') + "\n"; }
		if (!this.clean) { str+=iText('inspector_unsaved'); }
		if (this.uploading) { str+=' ' + iText('inspector_uploading'); }
		if (!this.clean || this.uploading) { str+="\n"; }

		// Number of nodes
		if (this.path[this.path.length-1]==this.path[0]) {
            str += iText('inspector_way_nodes_closed', this.path.length);
        } else {
            str += iText('inspector_way_nodes', this.path.length);
        }
		str+="\n";

		// Connections to other ways of same type
		var principal='';
		if      (this.attr['highway' ]) { principal='highway';  }
		else if (this.attr['waterway']) { principal='waterway'; }
		else if (this.attr['railway' ]) { principal='railway';  }
		var same=0; var different=0;
		var z=this.path; for (i in z) {
			var w=z[i].ways; for (id in w) {
				if (id!=this._name) {
					if (_root.map.ways[id].attr[principal]==this.attr[principal]) { same++; }
					else if (_root.map.ways[id].attr[principal]) { different++; }
				}
			}
		}

		if (this.attr[principal]==undefined) { 
            str += iText('inspector_way_connects_to', same);
		} else {
            str += iText('inspector_way_connects_to_principal', same, this.attr[principal], different, principal);
		}

		return "<p>"+str+"</p>";
	};



	Object.registerClass("way",OSMWay);


	// =====================================================================================
	// Drawing support functions

	// removeNodeFromWays - now see Node.removeFromAllWays

	// startNewWay		  - create new way from first node

	function startNewWay(node) {
		uploadSelected();
		_root.newwayid--;
		selectWay(newwayid);
		_root.poiselected=0;
		_root.map.ways.attachMovie("way",newwayid,++waydepth);
		_root.map.ways[newwayid].path[0]=_root.nodes[node];
		_root.map.ways[newwayid].redraw();
		_root.map.ways[newwayid].select();
		_root.map.ways[newwayid].clean=false;
		_root.nodes[node].addWay(newwayid);
		_root.map.anchors[0].startElastic();
		_root.drawpoint=0;
		markClean(false);
		setTooltip(iText('hint_drawmode'),0);
	}

	// addEndPoint(node object) - add point to start/end of line

	function addEndPoint(node) {
		var drawnode=_root.ws.path[_root.drawpoint];
		if (_root.drawpoint==_root.ws.path.length-1) {
			_root.ws.path.push(node);
			_root.drawpoint=_root.ws.path.length-1;
		} else {
			_root.ws.path.unshift(node);	// drawpoint=0, add to start
		}
		node.addWay(_root.wayselected);
	
		// Redraw line (if possible, just extend it to save time)
		if (_root.ws.getFill()>-1 || 
			_root.ws.path.length<3 ||
			_root.pointselected>-2 ||
			_root.ws.attr['oneway']) {
			_root.ws.redraw();
			_root.ws.select();
		} else {
			_root.ws.line.moveTo(drawnode.x,drawnode.y);
			_root.ws.line.lineTo(node.x,node.y);
			if (casing[_root.ws.attr['highway']]) {
				_root.map.areas[wayselected].moveTo(drawnode.x,drawnode.y);
				_root.map.areas[wayselected].lineTo(node.x,node.y);
			}
			_root.map.highlight.moveTo(drawnode.x,drawnode.y);
			_root.map.highlight.lineTo(node.x,node.y);
			_root.ws.direction();
			_root.ws.highlightPoints(5000,"anchor");
			removeMovieClip(_root.map.anchorhints);
			var z=_root.wayrels[_root.wayselected];
			for (var rel in z) { _root.map.relations[rel].redraw(); }
		}
		// Mark as unclean
		_root.ws.clean=false;
		markClean(false);
		_root.map.elastic.clear();
		var poslist=new Array(); poslist.push(_root.drawpoint);
		_root.undo.append(UndoStack.prototype.undo_addpoint,
						  new Array(new Array(_root.ws),poslist),
						  iText('action_addpoint'));
		updateInspector();
	}

	function stopDrawing() {
		_root.map.anchors[_root.drawpoint].endElastic();
		_root.drawpoint=-1;
		if (_root.ws.path.length<=1) { 
			// way not long enough, so abort
			_root.ws.removeNodeIndex();
			removeMovieClip(_root.map.areas[wayselected]);
			removeMovieClip(_root.ws);
			removeMovieClip(_root.map.anchors);
			updateInspector();
		}
		_root.map.elastic.clear();
		clearTooltip();
	};

	// cycleStacked	- cycle through ways sharing same point

	function cycleStacked() {
		if (_root.pointselected>-2) {
			stopDrawing();
			var id=_root.ws.path[_root.pointselected].id;
			var firstfound=0; var nextfound=0;
			for (qway in _root.map.ways) {
				if (qway!=_root.wayselected) {
					for (qs=0; qs<_root.map.ways[qway].path.length; qs+=1) {
						if (_root.map.ways[qway].path[qs].id==id) {
							var qw=Math.floor(qway);
							if (firstfound==0 || qw<firstfound) { firstfound=qw; }
							if ((nextfound==0 || qw<nextfound) && qw>wayselected) { nextfound=qw; }
						}
					}
				}
			}
			if (firstfound) {
				if (nextfound==0) { var nextfound=firstfound; }
				_root.map.ways[nextfound].swapDepths(_root.ws);
				_root.map.ways[nextfound].select();
			}
		}
	};

	// ================================================================
	// Way communication
	
	// whichWays	- get list of ways from remoting server

	function whichWays(force) {
		_root.lastwhichways=new Date();
		var within=(_root.edge_l>=_root.bigedge_l &&
					_root.edge_r<=_root.bigedge_r &&
					_root.edge_b>=_root.bigedge_b &&
					_root.edge_t<=_root.bigedge_t);
		if (_root.waycount>500) { purgeWays(); }
		if (_root.poicount>500) { purgePOIs(); }
		if (within && !force) {
			// we have already loaded this area, so ignore
		} else {
			whichresponder=function() {};
			whichresponder.onResult=function(result) {
				_root.whichreceived+=1;
				var code=result.shift(); var msg=result.shift(); if (code) { handleError(code,msg,result); return; }
				var waylist  =result[0];
				var pointlist=result[1];
				var relationlist=result[2];
				var s;

				for (i in pointlist) {										// POIs
					point=pointlist[i][0];									//  |
					if ((!_root.map.pois[point] || _root.map.pois[point].version!=pointlist[i][4]) && !_root.poistodelete[point]) {
						var a=getPOIIcon(pointlist[i][3]);					//  |
						if (a=='poi') { s=poiscale; } else { s=iconscale; }	//  |
						_root.map.pois.attachMovie(a,point,++poidepth);	//  |
						_root.map.pois[point]._x=long2coord(pointlist[i][1]);// |
						_root.map.pois[point]._y=lat2coord (pointlist[i][2]);// |
						_root.map.pois[point]._xscale=_root.map.pois[point]._yscale=s;
						_root.map.pois[point].version=pointlist[i][4];		//  |
						_root.map.pois[point].attr=pointlist[i][3];			//  |
						_root.map.pois[point].icon=a;						//  |
						_root.poicount+=1;									//  |
						if (point==prenode) { deselectAll(); prenode=undefined;
											  _root.map.pois[point].select(); }
					}
				}

				for (i in waylist) {										// ways
					way=waylist[i][0];										//  |
					if ((!_root.map.ways[way] || _root.map.ways[way].version!=waylist[i][1]) && !_root.waystodelete[way]) {
						_root.waystoload.push(way);
					}
				}
				
				for (i in relationlist) {
					rel = relationlist[i][0];
                    if (!_root.map.relations[rel] || _root.map.relations[rel].version!=relationlist[i][1]) {
						_root.relstoload.push(rel);
					}
                }

				if (preferences.data.limitways && _root.relstoload.length+_root.waystoload.length>1200) {
					_root.windows.attachMovie("modal","confirm",++windowdepth);
					_root.windows.confirm.init(275,100,new Array(iText('no'),iText('yes')),
						function(choice) {
							if (choice==iText('yes')) { 
								_root.waystoload=[];
								_root.relstoload=[];
								zoomTo(Math.min(_root.scale+2,_root.maxscale),_root.map._x*2-xradius,_root.map._y*2-yradius,true,true);
							} else {
								loadItems();
							}
						});
					_root.windows.confirm.box.createTextField("prompt",2,7,9,250,120);
					writeText(_root.windows.confirm.box.prompt,iText('prompt_manyways'));
				} else {
					loadItems();
				}

			};
			remote_read.call('whichways',whichresponder,_root.edge_l,_root.edge_b,_root.edge_r,_root.edge_t);
			_root.whichrequested+=1;
		}
	}

	// loadWay/loadRelation

	function loadItems() {
		while (_root.waystoload.length) { loadWay(_root.waystoload.pop()); }
		while (_root.relstoload.length) { loadRelation(_root.relstoload.pop()); }
		if (_root.edge_l<_root.bigedge_l ||
			_root.edge_r>_root.bigedge_r ||
			_root.edge_t>_root.bigedge_t ||
			_root.edge_b<_root.bigedge_b) { setBigEdges(); }
	}

	function loadWay(way) {
		_root.map.ways.attachMovie("way",way,++waydepth);
		_root.map.ways[way].load();
		_root.waycount+=1;
		_root.waysrequested+=1;
	}
	
	function loadRelation(rel) {
		_root.map.relations.attachMovie("relation",rel,++reldepth);
		_root.map.relations[rel].load();
		_root.relcount+=1;
		_root.relsrequested+=1;
	}
	
	function setBigEdges() {
		_root.bigedge_l=_root.edge_l; _root.bigedge_r=_root.edge_r;
		_root.bigedge_b=_root.edge_b; _root.bigedge_t=_root.edge_t;
	}

	// purgeWays - remove any clean ways outside current view
	
	function purgeWays() {
		for (qway in _root.map.ways) {
			if (qway==_root.wayselected) {
			} else if (!_root.map.ways[qway].clean) {
				_root.map.ways[qway].upload();
				uploadDirtyRelations();
			} else if (((_root.map.ways[qway].xmin<edge_l && _root.map.ways[qway].xmax<edge_l) ||
						(_root.map.ways[qway].xmin>edge_r && _root.map.ways[qway].xmax>edge_r) ||
					    (_root.map.ways[qway].ymin<edge_b && _root.map.ways[qway].ymax<edge_b) ||
						(_root.map.ways[qway].ymin>edge_t && _root.map.ways[qway].ymax>edge_t))) {
				removeMovieClip(_root.map.ways[qway]);
				removeMovieClip(_root.map.areas[qway]);
				_root.waycount-=1;
			}
		}
		setBigEdges();
	}

	function selectWay(id) {
		_root.lastwayselected=_root.wayselected;
		_root.wayselected=Math.floor(id);
		_root.ws=_root.map.ways[id];
		
		if (id==0) {
			_root.panel.advanced.disableOption(0);
			_root.panel.advanced.disableOption(1);
		} else {
			_root.panel.advanced.enableOption(0);
			_root.panel.advanced.enableOption(1);
		}
		updateInspector();
	}
	
	function renumberWay(ow,nw) {
		_root.map.ways[ow].renumberNodeIndex(nw);
		wayrels[nw]=wayrels[ow]; delete wayrels[ow];
		_root.map.ways[ow]._name=nw;
		renumberMemberOfRelation('Way', ow, nw);
		if (_root.map.areas[ow]) { _root.map.areas[ow]._name=nw; }
		if (_root.panel.t_details.text==ow) { _root.panel.t_details.text=nw; _root.panel.t_details.setTextFormat(plainText); }
		if (wayselected==ow) { selectWay(nw); }
	}
	
	function mergeWayKeepingID(w1,w2) {
		var t=(w1==_root.ws || w2==_root.ws);
		var w,s;
		if (Number(w1._name)<0 && Number(w2._name)>0) {
			s=w1.mergeAtCommonPoint(w2); w=w2;
		} else {
			s=w2.mergeAtCommonPoint(w1); w=w1;
		}
		if (s) { w.redraw(); if (t) { w.select(); } }
	}

	function uploadDirtyWays(allow_ws) {
		if (_root.sandbox) { return; }
		var z=_root.map.ways;
		for (i in z) {
			if (!_root.map.ways[i].clean && (i!=wayselected || allow_ws) && !_root.map.ways[i].hasDependentNodes()) { 
				_root.map.ways[i].upload();
			}
		}
	};

