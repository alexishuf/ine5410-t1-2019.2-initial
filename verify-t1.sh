#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      �<kw۶���_�0�Kʒ���]�um%��cgc�g-_Z�,�H$CR���?f�~���'��$��䤎���q|L��� 0�Q|A��x훯���66����h�O��i�7֛���F����7d�뱔�Y;!!�8z�F�p���ES������h���{�������:A}4���{���E��������z{�Ҹ���������څ�]8Ѹ���ޛ�Ӟ����YjV^�=�u�����;�����;d�WqG�,1R�I���xL=(�OH}D�T�!t0���I�`���?�O	z�Ƥ�^F. W���3圙'&�FȰ��4�&K	�����}��:�({�"hTX����{Ns����^��1���^2�a�o�s�k�q�?Dz�z��lH�wQ<t���nE�
]�2�7��z^H/�fU\/&�=��)��q���F0��d0v�* Y;�:C���N<F�g�Pi�CU	g1C��O�
ס��:tԘ� C�:�g�'�$�˕E~�V��B�C�2S L�#�x9�t�<�Hbw���g����9�&�B�B�4y�m���0$�����F�,��񻣣���A��W�fX}���3p��I�'�~�H��xJ���夘4j$r��Hv�e�@�Z1(�][#	{�e��¸	�0�U���7m��m����o�pPF��-@�o�l�`
Lg������ބz&c�"+��k��J��$��Z�@	4���A���0������F��w�����PS�&�_F�=��~鷭l�S�I5��$
��U;DV��=^Х�rM+y��H�#,s$��""�����19��gN�׽�6�/��y�g���U�k��
���ͳ��v^���d<)v�3\6B��V�p"f�f��ke\V�ge�C�ҏ}2�PǛŝŔ&�[ _�'�yN��#�j��� h���탴��+� ����݀JD��>�S�����O��f "��x2��ֹ��^Ug�s��)�snSV�kC�t�z.s(L��x���&�.�Z��+���E�#��vg�b����#�T�����9W'-ꩤ"Q�6!Ϛ�53h��6_��j�^�^�+��$�P2�/�H�d3�H�'�p��aӾ'M������y����.a^��%�1jxS#o����/���A��w|9�?:<��+�������"�g����M�� �}1Ҕ�$�����1��=?T��]�f�z����<f�m�c"�*����h7nT�����=¥��#J?���������6HQ�!���Y���H!��	�R��nOs͠#Y_N4�#�� ^^F�r��F�4�B��P���!�U$�Ԝ:�\���ďh�!X�h��-���PZ��y�8��N�Eƾ?���R��!����)eФ�(��Ɉ5��sT:�1�XS˥���h2��J�g����*oȱO�N�k'bR��5`��h��]+6DɎ�@�g_��,��I������Eb��N<c�	���JmNWw�$*	'
��x��t`bC��	)pMԄ��)�YYQ�Wufm��!�g�37�Cr�)�)���l�P�*A�:A�Hu1_'�2ƺ&��+�j���4P���Q�����-��p�o�fI�:����N.aw�#�t�h��Ԧ>`e3#_'r˶;8@s��J���A�h��JXS�a���5���N�!_�r���f6D��2Y��uOʻ�j�++v]�Q�w�o��$_�ۘtY�["�Th
6Ϡ<�X�mNkٱU� (
����޵3�T}ʓS|����P���W�[\վ�����j�J���_�ΐ֯7��:���Z��ߍ������C$������t�z{��Ve���q����?죓�W�����n��ǽ��;KTR���$s���$Yҫ5o6�T*7��!��:0�l������'Xg�؝C�u�L�*�>	�a���<������n|�#?����e+,�ų=q����%.c��D�y0�s�$���@��#��6�
�ސ$F�����H�Xg�s�hBi@�X��+r��d7�:${+�� �@+9���|�G�����S�&4t����+�MI�����!��)^z��ay!Ӊ��ĸd��~Bؠ� ]�9%uGUv�o�Z�D��|Nw��š?�Pa�E)�9,㩨�5�PzxZ��o$S�BɩI�
��:n�GdW�GF�x��p��"^$����ȭ�\B*,���9�����4�>��%E�{+;�on��$����۽��}�Ǣ����J����'�3��a�(B_��.4Xk����
�|9���g�a%��Rw .N��K�C�"�oD�I̶�pU�!�i?#g�%�0}�s4���������uXkƸ>ď�W������� ���<�~x���Rsۀ&�p� 3�i��p^����մ ]/A���r� �����q'��d�v�iY��<g�>�n/b�� 2�j2��E�JJX����m�%Xs�(�����w�)r�с����0���˛��F�K?Z@��6����bliP�<T[e^ng��+ ;x��4AQ>z�%װd �Z��
� dw7�\&Ɇ^W� _��@:�H)��˼%�NI�d���U�5T�:����6I�x����a5݂��$`,}CӣZ� �6�2�.�C��č�YL�#�7ؙ%wiY��>�)� U+b�.�6Z�6kk��Z��E���)�����;tb?�'y��{�c~����r�����IOݑ7�#b��;:<�라�{��ޏ�����l��5�9zt��#����d��8#�<;���X��O��6Z;�+�#8,����dJ;��Ma
v!3��П]��^�97e�Ps⃏��M#:�
IzYPO��A̖ư(�XQ�����3��ͼȽ�����JQ��̐AF9"s�%$� }�{?�=������v9쁝���:&��n�GX`�xKx��6��5 V�{4q��嶴�pU6I�x���b���n�Pc��5��5n��	�
�kG�4�PɊ�+-g�Ӭ.��%�c^EH�V_8�l�g��oV�o�d�5�:U��5��
���	#~�*V����-�+��a���;g~]�Q� �#W���fYL��7�a�Zjr�k����������o��s���F�q��4w�v"���	�a�e��Au&z��s[ϛ:�8��)ZC#�������iR�q|�ׇ��|�RsWb���V��כ��Ha8���`N;:�UW�pB6��B����,�L�!5��Y`UVT�s�}���Q������c��b�=:-�~�Χ3�
�1�I1��@@�SX����<1���+�	*��N��ڵS*��̛G%��
�f�J�)��{�u����;{acpg'��aG���{R�����yi���Tnu?r�w��VNXw�YH��!Cu�	�������D�)��5������4�W���5>�F�RI���CkF>3��J�Jb��Xq�N��1�4����D�'/a�b��|<��8+�;��b>7Ұ�\D�ݩl���2��:}�Y�[1RI6V���ZQ��HEƢ(X�R�z"I�+�&�2�~��Oȼ�+�'���Ci�`tߐ0 Ñ]�QI�\'�4-rdߓٖju[��LV��͉��"˫(b?+�4�S1�%��_D'c�i&�G�~�rŬ"$����$k���gY,�_��$��4�E���<J���R:��H�y��<-`KQh"�Y��4�hfa�Cm��"+"��z��W������=(�T��آ��2����J�AL��9y�g�0�l�Џ��7NH]�t��\a����{��>�
�
V|2����!S%,��8������v��]	 ����q�p��-g�F�-��s���pY�y�4A�a#}���30�X2&��gu ��Pd��,+}�ԘBt�6�`[L��.����E{g:YJ�K�.Y�܂K�D�uj�n�9.٠Uf��X��od�	c��8��,��Z��F��|N}9��{Z"�����\x	<�8ҳ4g���8�Y�� �S���c������I���p�F�	%Z^�Fs�,v�3鶡O�<��>v<KZ���b�Y�( ��Ű	��]Bv����M@�|�N��C�<*��ީ�8U��z�2�"�:�t>=�Q/E��j[����"�br������:�\н_�-8*𺲪�rH����s�zF�YkZp�:�'ٛ\qڽ��a�Q����㓟��_YE���_��}� ��@�u��_��{D;���ޝ"jA�: �ϭ���\T�b7�3Ƌ2L��������ĳ�<�Y�$���2�g�6�#�N9�(�RŃ����r�z��?Q����׀>_�_*é�>	�|jϙ|���@x(����w9"G�z������,G�x/5ߊA�J�D�"@T	h�g��\����Am�c�@�s�`�@J>vAH?�)^���j#\^��m�^�Ď���/;>;g��`��|�ڮ�Vk��F�h�լ�����m�>����Y_�z����F�[�h��R뫍 �W_��x������-�@�������M����=6Z�hȴ��+A~�,Wj������Oh���Sº�����&�����
[���9��e�I�.:!�.˃�w�x�	�AX��SN��sQ+��qijԣᝉG�JZ�_�}p0�8���M�.�}�&�X3�MiDԚ��˼�"�yp9��b1f�`O�С�vuZtL�=9�J F�;���O�~���8����r�4�Z穤7�fXw��x�8>���%
&�`Wƒ垯�4E7~��E�g��-������*�|�	�j�_m��dؚ=ND������.�poJq$�O��mä^����Y�\��.�G�!v%]?kW��n������r ��9�B.���V��jţ6���T�
������	�E�]�����=�������~�X�����}������ �(�/9&.�� *%��J�`L��qJ,��?N�F�UT�;=b�A�`��sA�������1d�	�Mo��c�k�|�� ,-������O������i���Ĺ�C��`�N)z���S����tMl�FO��N{q-#�0��;qH�y�d��v�h���XW؟\
���)ǚG���a��9�(����ݑ�H��7���3z���� �(���"�($��LTL�� 
V��᮴���X���_����S'bK��	3_O��\�-�<�GE�IW�/"�Ih��w��)��;�S���.Mbכ�Eb���$~�@rD%é@���ƈ�^�3�6��, 9��{��j�h���%,�0�E���t{ߑ�E����~��:���V.��������~zJhL�C|�QL�~Y+t�����ԁ߳�q����s���+?�W�9�O^;�r��u�{���t��d����/�~$&{��w����=�lw����6c��Ȫ�1P���M�Ư�wd�� ��4	����z��,WS2X�f�u��(?����i�r�G�G�� ����F�ɛ�1�t�� �
S0uc�֖��U���붝%�* �j��OT*�>�֚}`_Κ���U=�!���ONN��y_+}k�������9:����E��}yڱ�w�]���7����ω�����{�>=y�v��i5�/��ڎ0��l�_=:ͳ����_x�o�������ƣ��T�����mw�t����h{�C�̘��q6<D1Tq��Y�:sמμ��Kҋ�9JC���J�09�jhT�z�⭩�^:�l��<�� �m4���j���6Ltx�>��c����kU'���o{O�ݶ����)`�I$Gv��{�uZ�v�k�^�ٶ�:�D�lDQKJN���_{v��_=�	�bwf � ~�Q�6G8'�M���`0�f���Y��ҕ*�")>��ip@����^O�Mr��|3
{�iMR����!��F7��@=�S�*;"�{s!��	h��攀P5�0��;GGǺ�������98���V-� ^3[�(w(��
	6��e�{�;y	�jX���8�V�W#T0�)F���ݻX	���#��U�1;�0��!*t��_���j�������s�8eg�A�gq�t�Tƪ���FB��qT[ӏ��qTT��MDE$�f!����+[�?���g����b��V�-�-Y�jʊ5��G7����(=NȂSq�0�`qհ�����_���oq,a��G�0'��WԊ���(`%�D����~܋��4�a%O��BɈ0|(�xյ���g���R&hE�V$���d�Gg!��Y���L����X�*^o �ު��$�!��@�k>G��I[o�=��W	;V�"6�W�е�E��n�r�����@� �#V�ŉ`�D�Ӊ�V�C ����so�[1A�N�on���֋0�L.���Nv��ج]�Z��s�%KE�kh��)h��d��o$^{��B�sP����b��䰤���<<��J~"���-C�4�w�d�����L��rWI��N~�Im�0�M�4�v�,�t~I���RjPg0$��4$��do�����߼�ߞ�|���+v>��C��ZgG�|�S��G��X�*��S�S%Z�s����F�w�ǽ��yW�kE�[)�C�	es��i\7^X=j����5f�4Y����վ7Yo�Rj�D�J���?�i8$?ځ'�0U#�ֹ�'N9�2$��G��.S܋�Շ����m�ČA��M����d�[�)m_L[�F��o��`�7R"J��}�pG m,�����Y���� M)Wӻ��n	*���*�u���4�,�p1K����p�P��ף�jt�_��=ģ�s)6e�R���Zs���q��J�E g&E�|A��n2'ʨ!R+X���zk��Yző(�Wš?s��,=̡+�l��U�f�Q�M�/�.d�I\�
��h�g(������AծH�xdW՞JKF٣����l�&1M�!6̈́EY�͡$�LBF"W3�R�N'�r�l��i<AV7&��i�`C%��0߷�064��Sx��*ɽ�ʇ1k_KYL^�i�p+%ښ�XIwh[�Y��q)��N�L9��He'��B�}3E�P�D��L)�:+鹮�g�`��Y��XCݲv����>\���D�^\D�6Zƍ���|0��ڍ1ht#�!-۪\X����g]���e�|a}�x�R������B��an̷3Q�ȝ^e38�l��[Z��������׻/���+��m�+,�Q5�@��@����>�B#Fu�F�#��F�M��I���yֳ����?aE�|Е��XE�qF��~X{!�g��ADz�/���^5���Ç�g�8�a����Uf�������w�O������w��)��nEr0�#Ż��</��!�]�b�q2�5��ɏ׿�����!�)�}�1bM.���,)t��������F��io]:�뤃�:��roG�MC�iW\R�.q�*Guc94HX���%�����j&${���u��.7�n��8R&G�Z�2z
���d ٧�M a��$�eA�KM�nr>��f��͓i�{��ޥ	�͖��2���Ĺo^|���L����
�q��^9�΍���\�u���U^K%�?�SiZ�z�̱)vh�d��Z7�	W�����Zm9\n�+���I�UM�r+���9�	pDr���?ق��0��&�J}̵O�7jx�l�hg������w�������x,0�/��$g�C4�Il�Qtx:�'#��l��ds��N�b�p�:YҖy�'_J�Տ���NtuS|��l���F��H�T`l5�y�6���c�p�#�*4e�����VPj�t:�mB�"!��z�;'
q/GNe�,�dsZ5�Ol��׽۴P������J�a�<",�C�x��O��j��u��j"}
5���LG���YP�;�\���H��^��KR�r�^�]�K�?�
�yG:͖������e��*��L%@i�S��0��m�I��T���/H�ʋ��2�J+ŗ��X;����ᚐJ���z=�LƧ]\�w�|�FL8�}o��&D�rr�����b[�YѪTGr)~�*5�f�p��M���10	*�e�]���	�`��@�{CJ�K$V�W�,��������z�lq!dӪ�&�����O���t���v2���R:���*�R2���J�L�"��:Dݒ�R��ȁ�d���2��Zn��֑�%#g��Š��͸���f
�L}�?9����8�ȓ=Ç�AKp�8�`������UF���چ��+���MN���Œ���c�_���Lf�$l�0;�U��E�8����	�"����g^c�������m�I����5�����S�^B�
v�&�;��T�*�܎�=UI�m�͠,�U@iV�Ӭ��+� �&k�b�'^��/�<C�b���;)�}��gsC�rl�Fb���쟢B�=�v�!9��2�E<h�����[x-lQ�}��TC�Kg��ft^���{?��~��������A�X|��,RY5au%���AIm6�1)��*S3�E��A�+[<��e�NU�,���j<�a\��l�7S4��������JSS�4��Í�s��~�d�4���h���v=�Sz��Mq�Ry�B����<3�[]R��a���K6�E/�rp�����%���l31)�WNI䴲JWNU��Q�_��txtc��4�G:�O�/�M��i��7']"/+�.��2���bً�A�E3�0�Y���N�H� �^�a����hx��4�G ��U�_Q"�׌����*۾��2 ��]k��5ͷ"�5�Z�M=[{'�#��>���@�u�V=ټ�N��"�5��^[Lp�-��7�&^�r�Hr��z��j�!>����I"����܉E<~˞��ەs����b�|����[�i�@;`��-����e��4T��8J�=��I��jO��%��5５��(��x%��{ k�R��3�o�#s��Fb��Ӌ�F/��*#33h���ÜE����f����XCOTy�]�޸��@l�<�(�u7�4T�Џ4[�YU?(Lm�bβ@9�JgY��J�Fo����cb`5�L��S����,���Cq����^�F�m���v]�E���O�F�-�LH~bx�7�F�p
���l�#6
/��M������I�^��b�� @/�jMӦ�)�Jb~GFU&X�{2�kA�M���m闂��i-y�����fگ��F��4~%J�,��Hљgaڢ��矎���V,���)M��Y�T�Ȟ��Џi!0����J�?ǉk�p������7rB	�G<�����W��8�B"��U����TO�@w���|�3��5q3�fe]\P���!*�U�n��㺇��PyAwAf��%:Kz��:m��4�l�줷�u�� �xgmB����U�ˈ�&�#k��z���X�b���{�+�±� L�� b��#�J$lf���������"y$f�]��:B��?�N�YA*5��T*������#sV��n���q7&Oa�UG�*�p�6�}g�(�R�p;''��/";�Q� �{�t���׿ ����_5x�&<��cyUyێ2y��1��P�q2�M��n����2��b����J-!u���8	��8�/:f(
��C���A��!�f����H~����w�ͽ �t����V�J�1ƣzl�9)m�s�m&λa����A��	�S�h&�ͼ��
���un�&�QK_�%^ &���������d��GLԌ�Zέ)	gc��@U�2�񣞭�V�1C�[���盻/����n3�`~>��,� �xX�<m����;�B�bo4����w��5\�"]c#oH�3�Y3���\�|�ae9�g�9��`�+ǚ�	q��>{&/��)C[��$ɸ��㉺7z^�%]i#yn��G���37o����܏Q�m�c��C�&�o�9,o 컪	�rNZ��\�Q.��Dp^��9�oj���TH��G;��t�0��h���ջ�'�j��T��%N.bʲ�N;9�8`������� 
��O�(��Cf!��aT-��N(�	?��6Ì'�w8�$�ޔ���<rU��Q�����U��3@�"�Ґ����֫	���!�3Qw��j9�v�L�'"AM`����?5�d��1m!&	�:wJ����pP�Aȉ�"�7���T|��`v_�8�͕ҎO�W��
�sE�h�����S���ڛ�P?���-�V,>��e]��X_�O�?"�������쫴��]�,8e;U�<Ǣ�~�X���7��ʂ�������=X@if�$�z���BU�X��*��ʞ�-rU'��i�z�_z��\�(��wu-s���'�.����b��w�����a��Z�ʾ�Zp�_޽b<���Y�z/-)����KJ���I��Bi�qC����>)�5��j�V�RMb����T኏�0L~������;{uE^tp��Xx��)���[ �)m��T�7��.nOq�Ew'�X���e��
��f����=���+��@���л
���\T�>d ��+zu��k�!ae}�Ů��Yg�e-ʗPDY�ɼ+c�9<ۥ���є��>7 ����<��If����b���Rx%/������ڍ�>����cdE��#����3��&���󋉡�c-��w��+���#9+� �&֒���/F����|�ZO�C�z^]	�,/�dLڻ�m�[�U	�v��紞�F�����_���V�M���!r��)(t|��Cz�[Ӏ
��5�0�g���_9�����Չ�0�Y������U/s����e�~�ui��U�Fcv�&�8�;6	!H��������@	�Ou����Qa�CU���o(�iP{�h蹉%��X��Hf/M�cvX��娘��X�_>��<b�l�ӮYY:nc�)�ĒV��Ѯ������p$��Í���Qh���Ι"=���S��z������Ek��N��0�6��XXQv!�4�?�p�Ɇ}���ｸW(���[Z�a<�%�C�{����B���b����^�I�/��{���?�t1��RRe_�f�X�O8)�B�@�q�˧@���X·�;�ʣe:z���7�!�&O�K珗��v]P1�Nfr�M�Z��<i��:v4��r2el�1����e�O�@�pz:��y�pyn)�l��C΁��W\?Jn2�nu�՚�"!�F��Grŷx�e��ŵ���q��F� 	�l���w.��]�H�V��-QZ����E8��ȉ�.����BG�^|�|c7� 	���D��b��W>��5���t�e�$Œɞ �x���S�1�r��Y��v<�S���"�ٓ'y���g�?3�?��X�o��]���Ω_82�>��aKJ0F�J�[���g�c-��	�Ȋ]�V	�A�
����~;xur��dC��!���3�.;��p��:w�Vx��ti%�Krj��	T%Y'��߲U�j��7~��l��~�:�%ۇv�|XcW�+�݆�w}6v�
�3�^��� _�����������}��+{���m?��T�Jg?�2��pZ�2t`�Ι�'1���p:��A�t$��[c��_p�Zr�ъ.�
i�Yi���j�&"�{v�����-'ʟ�t4�[����	z�d|��m���P�]����S�����%�|�Pr�i�	[��l����=Y�YFf�:4~@����@ ����F����p$�5����j�{V���V��s�?T����2a�Q���Vu�M���<�t�:Tr��)j�m�8wSn�?6���Յ������{�(�_I�\,��F��_[��Qv���g��e�������9�Z۽Ã�ݯ{[��WG[; ����_{�u�Z����i���՗�Ǎ�WD�&�<i8w88̟�Zg��i�z�`��ʣ�H\��o������ڢ���%����y��r�xu��5����_�E�^@J`��=�L]?fn�	J_���ڄZ`j��E��y�i�b^���Bx̂��m�I8
��M.�x�d�#�H B�sEt	e#l#��¤�N��炕���>��"�v�]�:�|�xp�oX��������ԡ-T}/@�BxP}��.� �����9�|�s�u/&��z����wЊ�>�	 �#o����q���Z�t��F��[��ȋ\T�;0$�b��OP�o��o����;���Agy�}2�C�wG��t�QW�f����"-`��&�ù�xc�� ��h �|������92�_@����/j���l��M$�$rG1�����%���eyC)Uxg�[� �-Y2|8���r��X���7�`���G�M��pLdGEPw16u:2v'��4��{�5o�^;�E_u�_��.`��q������#�#��pJM9����Y��b�1[��Xn�5xO���@�6Diɒ�]�D��(־p0��E�p��"�A/׷�����q+�ފ/� ��tso��WH�q�L��F�W�=�;?|�C���Z��@{\k���F�!z��_Ht�+_���@����/���~u�y�{���������;}w��AYC�B�_�p�i�H�;�3�'��9U|�}�����h���s��Rb����c��p0ļX#��Ff������v�@�e�Wj�V�=��̫U�v�7�ȹ�����
r��m�f��k��V:p���E.m��W�?�˅���f �x��O+�5����J:m"\$�>� ��09�:2�?\f>��G���m�l}5l�H4l,��$�M�la�%�֑��=�^;�R�u�γ�Hw�\�p�dл��cڄ;��@x�*P��)����'����B�� G�����}����7�،�
o�o��zȆ(����<��e(c(1������������/�F���ldB�jB�H�����=w�Zy���N�8r@쭣DQ����(~1��4@27T��f������/��\�.��\�۸�q�Lȫ%r:��W����xD���јx�*$o����C��s����a����c�>`���`C� �S�#��bw���C(�D�N�*�0u^�����z�f����͠Q#�(�X�-nv�`j��{�	�|s���ͣ��N�%l�������Dq�;ɒ�h��{��)�1��+p
j�_-�{'2��׭�-� ���)�ιs'Q���0_ڰ�-�u��(Ǡ���9�5%��pR����+X:&����K.W ��-��me�Ν�{��v���5	� o���	}|�+
�wI���T�P�ڪ�ir�����,�Ü#��^�.���C.�A.��E�#)�?�q�i*��!] u�C�4��mE,�5q�ށ��]2�[��q4ыߤ�m#�p��/�f�lW6�\u%��i�����@�����c}�@��6�E�+ HL+MJ'G_�֝;_�t2־C���������:;8ޚx}�I�Y��g���t�S}ᓘ}WCwD��5tXk�6�{�]�/���Rt���p�N#Z�a�Fn\�uy��.;�G��-���( ��ޮ��%+�P�S�`5���D]x��`�׿L�>oZ,C����+Lp�6�"���7i��w���l�3?�$�F2k묋j�'�QR�"�1݈��i�mo�sݸ}x���{��x=]�Sɖ#���n�Ys����ċ�Ju4�p����Li���Ǵ�pƨ�h�TwR�KU�7QxQC>uc���D3���OZ�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY�EY��)���!E @ 