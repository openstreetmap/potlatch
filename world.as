
	// =====================================================================================
	// Potlatch co-ordinate handling

	// updateCoords - update all co-ordinate global variables

	function updateCoords(tx,ty) {
		_root.bscale=Math.pow(2,_root.scale-13);
		_root.xradius=Stage.width/2;
		_root.yradius=(Stage.height-100)/2;

		_root.map._x=tx; _root.map._y=ty;
		_root.map._xscale=100*bscale;
		_root.map._yscale=100*bscale;

		_root.edge_t=coord2lat ((-_root.map._y          )/bscale);
		_root.edge_b=coord2lat ((-_root.map._y+2*yradius)/bscale);
		_root.edge_l=coord2long((-_root.map._x          )/bscale);
		_root.edge_r=coord2long((-_root.map._x+2*xradius)/bscale);
	}

	// lat/long <-> coord conversion

	function lat2coord(a)	{ return -(lat2y(a)-basey)*masterscale; }
	function coord2lat(a)	{ return y2lat(a/-masterscale+basey); }
	function long2coord(a)	{ return (a-baselong)*masterscale; }
	function coord2long(a)	{ return a/masterscale+baselong; }
	function y2lat(a) { return 180/Math.PI * (2 * Math.atan(Math.exp(a*Math.PI/180)) - Math.PI/2); }
	function lat2y(a) { return 180/Math.PI * Math.log(Math.tan(Math.PI/4+a*(Math.PI/180)/2)); }
	function centrelat(o)  { return  coord2lat((yradius-_root.map._y-o)/Math.pow(2,_root.scale-13)); }
	function centrelong(o) { return coord2long((xradius-_root.map._x-o)/Math.pow(2,_root.scale-13)); }

	// resizeWindow - user has enlarged/shrunk window

	function resizeWindow() {
		// resize Yahoo
		clearInterval(_root.yahooresizer);
		_root.yahoo.myMap.setSize(Stage.width,Stage.height-100);
		// resize main mask and panel
		_root.masksquare._height=
		_root.panel._y=Stage.height-100;
		_root.masksquare._width=Stage.width;
		// resize other stuff
		_root.waysloading._x=
		_root.tooltip._x=Stage.width-120;
		_root.practice._x=Stage.width-97; _root.practice._y=Stage.height-122;
		// note time, so we can issue a whichWays soon
		_root.lastresize=new Date();
	}

	// updateLinks - update view/edit tabs

	function updateLinks() {
//		if (winie) { fscommand("maplinks",centrelong(0),centrelat(0),_root.scale); } else { 
		getURL("javascript:updatelinks("+centrelong(0)+","+centrelat(0)+","+_root.scale+")");
	}

	// =====================================================================================
	// Zoom

	// zoomIn, zoomOut, changeScaleTo - change scale functions
	
	function zoomIn() {
		if (_root.scale<_root.maxscale) {
			if (_root.waycount>500) { purgeWays(); }
			if (_root.poicount>500) { purgePOIs(); }
			zoomTo(_root.scale+1,_root.map._x*2-xradius,_root.map._y*2-yradius,false);
		}
	}
	
	function zoomOut() {
		if (_root.scale>_root.minscale) {
			zoomTo(_root.scale-1,(_root.map._x+xradius)/2,(_root.map._y+yradius)/2,true);
		}
	}

	function zoomTo(newscale,newx,newy,ww) {
		blankTileQueue();
		changeScaleTo(newscale);
		updateCoords(newx,newy);
		updateLinks();
		redrawBackground();
		resizePOIs();
		if (ww) { whichWays(); }
		for (qway in _root.map.ways) { _root.map.ways[qway].redraw(); }
		if (_root.wayselected) {
			_root.ws.highlight();
			_root.ws.highlightPoints(5000,"anchor");
		}
		restartElastic();
	}

	function changeScaleTo(newscale) {
		_root.map.tiles[_root.scale]._visible=false; _root.scale=newscale;
		_root.map.tiles[_root.scale]._visible=true;
		if (_root.scale==_root.minscale) { _root.i_zoomout._alpha=25;  }
									else { _root.i_zoomout._alpha=100; }
		if (_root.scale==_root.maxscale) { _root.i_zoomin._alpha =25;  }
									else { _root.i_zoomin._alpha =100; }
		_root.tolerance=4/Math.pow(2,_root.scale-13);
	}

	// =====================================================================================
	// Backgrounds

	function setBackground(n) {
		preferences.data.baselayer=n;
		preferences.flush();
		redrawBackground(); 
	}

	function redrawBackground() {
		var alpha=100-50*preferences.data.dimbackground;
		switch (preferences.data.baselayer) {
			case 0: _root.yahoo._visible=false;	// none
					_root.map.tiles._visible=false;
					break;
			case 2: if (!_root.yahooloaded) {	// Yahoo
						loadMovie(yahoourl,_root.yahoo); _root.yahooloaded=true;
						_root.yahoo.swapDepths(_root.masksquare);
						_root.yahoorightsize=false;
//						_root.yahoo.setMask(_root.masksquare2);
					}
					_root.yahoo._visible=true;
					_root.yahoo._alpha=alpha;	
					_root.yahoo._x=0;
					_root.yahoo._y=0;
					_root.ylat=centrelat(_root.bgyoffset);
					_root.ylon=centrelong(_root.bgxoffset);
					_root.yzoom=18-_root.scale;
					_root.map.tiles._visible=false;
					break;
			case 1: ; // OpenAerialMap
			case 3: ; // Mapnik
			case 4: ; // Osmarender
					if (_root.tilesetloaded!=preferences.data.baselayer) {
						_root.tilesetloaded=preferences.data.baselayer;
						initTiles();
					}
					_root.map.tiles._visible=true;
					_root.yahoo._visible=false;
					break;
		}
	}
