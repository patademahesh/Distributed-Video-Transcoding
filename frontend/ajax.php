<?php
/**
 * Created by IntelliJ IDEA.
 * User: adarshs
 * Date: 30/12/14
 * Time: 1:36 PM
 * To change this template use File | Settings | File Templates.
 */
    include_once ("conn.php");

    $queryAppend = '';
    if (isset($_REQUEST['p']) && $_REQUEST['p'] != '') {
        $queryAppend = " AND cp = '" . $_REQUEST['p'] . "'";
    }

    if(isset($_REQUEST['res']) && $_REQUEST['res'] != ''){
        $res = $_REQUEST['res'];
    }

    if($res == 'INPROCESS'){
        echo  in_process($_Link, $queryAppend);
    }elseif($res == 'COMPLETED'){
        echo  completed($_Link, $queryAppend);
    }elseif($res == 'FAILURE'){
        echo  failure($_Link, $queryAppend);
    }elseif($res == "CLEAR"){
	failureClear($_Link, $_REQUEST['p'], $_REQUEST['id']);
    }

    function failureClear($_Link,$p,$id){
	if($id > 0 && !empty($id)){
                $updateQuery = "UPDATE jobs SET job_status = 999 WHERE job_id = ".$id;
                $res = mysqli_query($_Link, $updateQuery);
			
		$queryAppend = '';
		if (isset($p) && $p != '') {
	        	$queryAppend = " AND cp = '" . $p . "'";
    		}
		
		echo failure($_Link, $queryAppend);
        }    
    }

    function in_process($_Link, $queryAppend)
    {
        /* INPROCESS */
        $sql = "SELECT * FROM jobs WHERE job_status < (no_nodes+1) AND node_failed is null AND job_failed is null" . $queryAppend;
        $res = mysqli_query($_Link, $sql);
        $html = "";
        while ($rec = mysqli_fetch_array($res)) {
	   if($rec['curmaster'] != NULL ){
		$html .= "<div style='color:green'>" . $rec['name'] . " (" . $rec['cp'] . ") :  Master is Processing ( ".$rec['curmaster']." )</div>";
	   }elseif($rec['no_nodes'] > $rec['job_status']){
		$html .= "<div style='color:blue'>" . $rec['name'] . " (" . $rec['cp'] . ") : Node is Processing</div>";
	   }else{
		$html .= "<div style='color:yellow'>" . $rec['name'] . " (" . $rec['cp'] . ") is Waiting for Master to takeover</div>";
	   }
        }
        return $html;
    }


    function completed($_Link, $queryAppend)
    {
        /* COMPLETED */
        $sql = "SELECT * FROM jobs WHERE job_status=(no_nodes+1) AND node_failed is null AND job_failed is null" . $queryAppend." order by job_id desc";
        $html = "";
        $res = mysqli_query($_Link, $sql);
        while ($rec = mysqli_fetch_array($res)) {
            $html .= "<div style='color:green'>" . $rec['name'] . " (" . $rec['cp'] . ") is Successfully Completed</div>";
        }
        return $html;

    }

    /* FAILURE */
    function failure($_Link, $queryAppend)
    {
        $sql = "SELECT * FROM jobs WHERE job_status < (no_nodes+1) AND (node_failed is not null or job_failed is not null)" . $queryAppend;
        $html = "";
        $res = mysqli_query($_Link, $sql);
        while ($rec = mysqli_fetch_array($res)) {
            $html .= "<div style='color:red'>" . $rec['name'] . " (" . $rec['cp'] . ") is Failed : <a href='javascript:void(0);' onclick=\"javascript:clearData('CLEAR', '".$_REQUEST['p']."', '".$rec['job_id']."')\">Clear</a></div>";
            $html .= "<ul>";
            if ($rec['node_failed'] != null) {
                $html .= "<li>" . $rec['node_failed'] . "</li>";
            }
            if ($rec['job_failed'] != null) {
                $html .= "<li>" . $rec['job_failed'] . "</li>";
            }
            $html .= "</ul>";
        }
        return $html;
    }

?>

