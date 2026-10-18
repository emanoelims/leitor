defmodule Leitor.Dictionary.PronunciationTest do
  use ExUnit.Case, async: true

  alias Leitor.Dictionary.Pronunciation

  doctest Pronunciation

  test "respells IPA with Brazilian spelling, syllables and stress" do
    for {ipa, hint} <- [
          {"bɪˈkʌm", "bi-KÂM"},
          {"ˈsævəri", "SÉ-vâ-ri"},
          {"ɪkˈspɛrəmənt", "ik-SPÉ-râ-mânt"},
          {"kənˈtɛnʃəs", "kân-TÉN-châs"},
          {"ˈstrɛtʃərz", "STRÉ-tchârz"},
          {"wɪˈðaʊt", "ui-THAUT"},
          {"ˈdʒɑni", "DJÁ-ni"},
          {"ˈsinjər", "SI-niâr"},
          {"ˈænjuəˌlaɪz", "É-niu-â-laiz"},
          {"ˌæpəˈstɑlɪk", "é-pâ-STÁ-lik"},
          {"əˈkɔrdns", "â-KÓR-dâns"},
          {"ˈbætlmənt", "BÉ-râl-mânt"},
          {"ˈɡɪvɪŋ", "GUI-ving"},
          {"plæˈstɪsəti", "plé-STI-ssâ-ri"},
          {"ˈpɜrtʃəsɪŋ", "PÂR-tchâ-ssing"}
        ] do
      assert Pronunciation.respell(ipa) == hint, "#{ipa}: #{Pronunciation.respell(ipa)}"
    end
  end

  test "writes the American flap as r only before an unstressed vowel" do
    assert Pronunciation.respell("ˈsɪti") == "SI-ri"
    assert Pronunciation.respell("ˈpɑrti") == "PÁR-ri"
    assert Pronunciation.respell("ˈmɪdəl") == "MI-râl"
    assert Pronunciation.respell("əˈtæk") == "â-TÉK"
    assert Pronunciation.respell("ˈtɔkɪŋ") == "TÓ-king"
    assert Pronunciation.respell("ˈwɔɾər") == "UÓ-râr"
  end

  test "accepts slashes, brackets, length marks and unknown symbols" do
    assert Pronunciation.respell("[ˈwɔːtə(r)]") == "UÓ-râr"
    assert Pronunciation.respell("/sti:l/") == "STIL"
    assert Pronunciation.respell("ʃʊd") == "CHUD"
    assert Pronunciation.respell("ˌpʊl ˈɔf") == "pul óf"
  end
end
